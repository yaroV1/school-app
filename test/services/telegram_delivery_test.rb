require "test_helper"

class TelegramDeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @settings = Rails.application.config.x.telegram
    Rails.application.config.x.telegram = ActiveSupport::OrderedOptions.new.update(app_url: "https://school.example")
    @exam = create_exam!(users(:one), status: :published, title: "Algebra")
    @student = users(:one).students.create!(name: "Ada", telegram_chat_id: 123456789012)
    @assignment = @exam.assignments.create!(student: @student)
  end

  teardown do
    Rails.application.config.x.telegram = @settings
  end

  test "each recipient receives only their own link and replayed jobs do not resend" do
    second = @exam.assignments.create!(student: users(:one).students.create!(name: "Grace", telegram_chat_id: 987654321))
    calls = []
    replacing(TelegramBot, :send_message, ->(**message) { calls << message }) do
      [ @assignment, second ].each do |assignment|
        assert TelegramDelivery.enqueue(assignment)
        request_id = assignment.reload.telegram_request_id
        2.times { TelegramDeliveryJob.perform_now(assignment.id, request_id) }
        assert_equal "sent", assignment.reload.telegram_status
        assert_not_nil assignment.telegram_sent_at
      end
    end
    assert_equal [ 123456789012, 987654321 ], calls.map { |message| message[:chat_id] }
    assert_includes calls.first[:text], "https://school.example/t/#{@assignment.access_token}"
    assert_not_includes calls.first[:text], second.access_token
    assert_includes calls.last[:text], "https://school.example/t/#{second.access_token}"
    assert_not_includes calls.last[:text], @assignment.access_token
    arguments = enqueued_jobs.map { |job| job[:args] }.to_json
    assert_not_includes arguments, @assignment.access_token
    assert_not_includes arguments, second.access_token
    assert_not_includes arguments, "123456789012"
  end

  test "double clicks do not enqueue twice and an old attempt cannot overwrite a retry" do
    freeze_time
    assert TelegramDelivery.enqueue(@assignment)
    old_id = @assignment.reload.telegram_request_id
    assert_not TelegramDelivery.enqueue(@assignment)
    assert_enqueued_jobs 1, only: TelegramDeliveryJob
    travel 5.minutes do
      assert TelegramDelivery.enqueue(@assignment)
      assert_not_equal old_id, @assignment.reload.telegram_request_id
      replacing(TelegramBot, :send_message, ->(**) { raise "old request was sent" }) do
        TelegramDeliveryJob.perform_now(@assignment.id, old_id)
      end
      assert_equal "queued", @assignment.reload.telegram_status
    end
  end

  test "revocation closing archive and recipient changes cancel queued delivery" do
    changes = [
      -> { @assignment.revoke! },
      -> { @exam.close! },
      -> { @student.archive! },
      -> { @student.update!(telegram_chat_id: nil) },
      -> { @student.update!(telegram_chat_id: 777) }
    ]
    changes.each do |change|
      @exam.update!(status: :published)
      @student.update!(archived_at: nil, telegram_chat_id: 123456789012)
      @assignment.update!(revoked_at: nil, telegram_status: "unsent")
      assert TelegramDelivery.enqueue(@assignment)
      request_id = @assignment.reload.telegram_request_id
      change.call
      replacing(TelegramBot, :send_message, ->(**) { raise "stale delivery was sent" }) do
        TelegramDeliveryJob.perform_now(@assignment.id, request_id)
      end
      assert_equal "failed", @assignment.reload.telegram_status
      assert_equal "changed", @assignment.telegram_error
    end
  end

  test "regenerating a token clears old success and invalidates queued work" do
    assert TelegramDelivery.enqueue(@assignment)
    old_id = @assignment.reload.telegram_request_id
    @assignment.regenerate_token!
    replacing(TelegramBot, :send_message, ->(**) { raise "old token was sent" }) do
      TelegramDeliveryJob.perform_now(@assignment.id, old_id)
    end
    assert_equal "unsent", @assignment.reload.telegram_status
    @assignment.update!(telegram_status: "sent", telegram_sent_at: Time.current)
    @assignment.regenerate_token!
    assert_equal "unsent", @assignment.reload.telegram_status
    assert_nil @assignment.telegram_sent_at
  end

  test "blocked rate limited and uncertain results are not successful or automatically retried" do
    %w[blocked rate_limited unknown].each do |code|
      assert TelegramDelivery.enqueue(@assignment)
      request_id = @assignment.reload.telegram_request_id
      replacing(TelegramBot, :send_message, ->(**) { raise TelegramBot::Error, code }) do
        TelegramDeliveryJob.perform_now(@assignment.id, request_id)
      end
      assert_equal "failed", @assignment.reload.telegram_status
      assert_equal code, @assignment.telegram_error
      assert_nil @assignment.telegram_sent_at
    end
    assert_enqueued_jobs 3, only: TelegramDeliveryJob
  end

  test "queue insertion failure is visible and can be retried" do
    replacing(TelegramDeliveryJob, :set, ->(**) { raise ActiveJob::EnqueueError, "Queue unavailable" }) do
      assert_not TelegramDelivery.enqueue(@assignment)
    end
    assert_equal "failed", @assignment.reload.telegram_status
    assert_equal "queue_failed", @assignment.telegram_error
    assert TelegramDelivery.enqueue(@assignment)
  end
end
