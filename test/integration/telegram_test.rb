require "test_helper"

class TelegramTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @settings = Rails.application.config.x.telegram
    Rails.application.config.x.telegram = ActiveSupport::OrderedOptions.new.update(
      bot_token: "test-token", bot_username: "school_test_bot", webhook_secret: "webhook-test-secret",
      app_url: "https://school.example")
    @teacher = users(:one)
    @group = @teacher.class_groups.create!(name: "Class")
    @student = @teacher.students.create!(name: "Ada", telegram_username: "@Ada_123")
    @group.add_student!(@student)
    @exam = create_exam!(@teacher, class_group: @group, status: :published)
    @assignment = @exam.assignments.create!(student: @student)
  end

  teardown do
    Rails.application.config.x.telegram = @settings
  end

  test "private start requests require teacher approval before any test can be sent" do
    webhook
    assert_response :success
    assert_equal 123456789012, @student.reload.telegram_pending_chat_id
    assert_nil @student.telegram_chat_id
    assert_equal "Ada Telegram", @student.telegram_pending_name
    assert_equal I18n.t("telegram.bot.pending"), response.parsed_body["text"]
    assert_not_includes response.body, @assignment.access_token

    sign_in_as @teacher
    get student_path(@student)
    assert_select "input[name=chat_id][value='123456789012']"
    assert_select "button", text: I18n.t("telegram.connection.confirm")
    post test_telegram_deliveries_path(@exam), params: { send_all: "1" }
    assert_enqueued_jobs 0, only: TelegramDeliveryJob

    post student_telegram_connection_path(@student), params: { chat_id: "123456789012" }
    assert_equal 123456789012, @student.reload.telegram_chat_id
    assert_nil @student.telegram_pending_chat_id
    webhook
    assert_equal I18n.t("telegram.bot.connected"), response.parsed_body["text"]
    assert_nil @student.reload.telegram_pending_chat_id
  end

  test "missing or wrong webhook authentication does not mutate students" do
    [ nil, "wrong-secret" ].each do |secret|
      webhook(secret: secret)
      assert_response :unauthorized
      assert_nil @student.reload.telegram_pending_chat_id
    end
    TelegramBot.settings.webhook_secret = nil
    webhook(secret: nil)
    assert_response :unauthorized
  end

  test "group messages and messages impersonating another private sender are ignored" do
    webhook(chat: { id: -100123, type: "supergroup" })
    assert_response :success
    assert_empty response.body
    assert_nil @student.reload.telegram_pending_chat_id
    webhook(chat: { id: 998877, type: "private" })
    assert_nil @student.reload.telegram_pending_chat_id
  end

  test "class token scopes nickname matching even when another teacher has the same username" do
    other = users(:two)
    foreign_group = other.class_groups.create!(name: "Other class")
    foreign_student = other.students.create!(name: "Other Ada", telegram_username: "ada_123")
    foreign_group.add_student!(foreign_student)
    webhook(text: "/start #{foreign_group.telegram_join_token}")
    assert_equal 123456789012, foreign_student.reload.telegram_pending_chat_id
    assert_nil @student.reload.telegram_pending_chat_id

    @group.class_memberships.destroy_all
    webhook
    assert_equal I18n.t("telegram.bot.not_matched"), response.parsed_body["text"]
    assert_nil @student.reload.telegram_pending_chat_id
  end

  test "unmatched missing or archived usernames do not bind" do
    webhook(from: { id: 123456789012, username: "nobody", first_name: "Ada" })
    assert_nil @student.reload.telegram_pending_chat_id
    webhook(from: { id: 123456789012, first_name: "Ada" })
    assert_nil @student.reload.telegram_pending_chat_id
    @student.archive!
    webhook
    assert_nil @student.reload.telegram_pending_chat_id
  end

  test "a new claimant cannot replace a pending or confirmed account" do
    webhook
    webhook(chat: { id: 999, type: "private" }, from: { id: 999, username: "ada_123" })
    assert_equal 123456789012, @student.reload.telegram_pending_chat_id
    sign_in_as @teacher
    post student_telegram_connection_path(@student), params: { chat_id: "999" }
    assert_nil @student.reload.telegram_chat_id
    post student_telegram_connection_path(@student), params: { chat_id: "123456789012" }
    webhook(chat: { id: 999, type: "private" }, from: { id: 999, username: "ada_123" })
    assert_equal 123456789012, @student.reload.telegram_chat_id
    assert_nil @student.telegram_pending_chat_id
  end

  test "teachers cannot approve disconnect or send for another owner" do
    webhook
    sign_in_as users(:two)
    post student_telegram_connection_path(@student), params: { chat_id: "123456789012" }
    assert_response :not_found
    delete student_telegram_connection_path(@student)
    assert_response :not_found
    post test_telegram_deliveries_path(@exam), params: { send_all: "1" }
    assert_response :not_found
    assert_enqueued_jobs 0, only: TelegramDeliveryJob
    assert_nil @student.reload.telegram_chat_id
    assert_equal 123456789012, @student.telegram_pending_chat_id
  end

  test "one Telegram account cannot be confirmed as two students of a teacher" do
    @teacher.students.create!(name: "Already linked", telegram_chat_id: 123456789012)
    webhook
    sign_in_as @teacher
    post student_telegram_connection_path(@student), params: { chat_id: "123456789012" }
    assert_redirected_to @student
    assert_equal I18n.t("telegram.connection.already_used"), flash[:alert]
    assert_nil @student.reload.telegram_chat_id
  end

  test "reject and disconnect clear the binding without affecting nickname" do
    webhook
    sign_in_as @teacher
    delete student_telegram_connection_path(@student)
    assert_nil @student.reload.telegram_pending_chat_id
    webhook
    post student_telegram_connection_path(@student), params: { chat_id: "123456789012" }
    delete student_telegram_connection_path(@student)
    assert_nil @student.reload.telegram_chat_id
    assert_equal "ada_123", @student.telegram_username
  end

  test "contact forms normalize usernames but never permit Telegram IDs" do
    sign_in_as @teacher
    patch student_path(@student), params: { student: { telegram_username: " @New_Name ", telegram_chat_id: 987, telegram_pending_chat_id: 987 } }
    assert_equal "new_name", @student.reload.telegram_username
    assert_nil @student.telegram_chat_id
    assert_nil @student.telegram_pending_chat_id
    post class_group_students_path(@group), params: { student: { name: "Grace", telegram_username: "@Grace_42", telegram_chat_id: 987 } }
    grace = @teacher.students.find_by!(name: "Grace")
    assert_equal "grace_42", grace.telegram_username
    assert_nil grace.telegram_chat_id
    get edit_student_path(@student)
    assert_select "input[name='student[telegram_username]'][value=new_name]"
    get students_class_group_path(@group)
    assert_select "a[href=?]", TelegramBot.join_url(@group)
  end

  test "selected dispatch ignores foreign assignments and does not implicitly send everyone" do
    @student.update!(telegram_chat_id: 123456789012)
    second = @teacher.students.create!(name: "Grace", telegram_chat_id: 987654321)
    second_assignment = @exam.assignments.create!(student: second)
    foreign_exam = create_exam!(users(:two), status: :published)
    foreign = foreign_exam.assignments.create!(student: users(:two).students.create!(name: "Other", telegram_chat_id: 777))
    sign_in_as @teacher
    post test_telegram_deliveries_path(@exam), params: { assignment_ids: [ @assignment.id, foreign.id ] }
    assert_enqueued_jobs 1, only: TelegramDeliveryJob
    assert_equal "queued", @assignment.reload.telegram_status
    assert_equal "unsent", second_assignment.reload.telegram_status
    assert_equal "unsent", foreign.reload.telegram_status
    post test_telegram_deliveries_path(@exam)
    assert_enqueued_jobs 1, only: TelegramDeliveryJob
    get manage_test_assignments_path(@exam)
    assert_select "form#bulk-revoke button[formaction=?]", test_telegram_deliveries_path(@exam)
    assert_select "form form", false
    assert_select "tr#assignment_#{@assignment.id} button[disabled]"
  end

  test "send all skips disconnected archived revoked and already queued assignments" do
    @student.update!(telegram_chat_id: 123456789012)
    [ {}, { telegram_chat_id: 789, archived_at: Time.current }, { telegram_chat_id: 456 } ].each_with_index do |attrs, i|
      student = @teacher.students.create!({ name: "Skipped #{i}" }.merge(attrs))
      @exam.assignments.create!(student: student, revoked_at: i == 2 ? Time.current : nil)
    end
    sign_in_as @teacher
    2.times { post test_telegram_deliveries_path(@exam), params: { send_all: "1" } }
    assert_enqueued_jobs 1, only: TelegramDeliveryJob
    assert_equal "queued", @assignment.reload.telegram_status
  end

  test "draft exams and missing bot settings disable dispatch" do
    @student.update!(telegram_chat_id: 123456789012)
    sign_in_as @teacher
    @exam.update!(status: :draft)
    post test_telegram_deliveries_path(@exam), params: { send_all: "1" }
    assert_enqueued_jobs 0, only: TelegramDeliveryJob
    @exam.update!(status: :published)
    TelegramBot.settings.bot_token = nil
    post test_telegram_deliveries_path(@exam), params: { send_all: "1" }
    assert_enqueued_jobs 0, only: TelegramDeliveryJob
    get students_class_group_path(@group)
    assert_select "a[href^='https://t.me/']", false
    assert_includes response.body, I18n.t("telegram.not_configured")
  end

  test "webhook works without browser CSRF but teacher actions still require it" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    webhook
    assert_response :success
    sign_in_as @teacher
    post student_telegram_connection_path(@student), params: { chat_id: "123456789012" }
    assert_response :unprocessable_entity
    assert_nil @student.reload.telegram_chat_id
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "bulk selection form supports either action with CSRF protection and without Turbo headers" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @student.update!(telegram_chat_id: 123456789012)
    sign_in_as @teacher
    get manage_test_assignments_path(@exam)
    token = css_select("form#bulk-revoke input[name=authenticity_token]").first["value"]
    post test_telegram_deliveries_path(@exam), params: { assignment_ids: [ @assignment.id ], authenticity_token: token }
    assert_redirected_to manage_test_assignments_path(@exam)
    assert_equal "queued", @assignment.reload.telegram_status
    post bulk_revoke_test_assignments_path(@exam), params: { assignment_ids: [ @assignment.id ], authenticity_token: token }
    assert_redirected_to manage_test_assignments_path(@exam)
    assert @assignment.reload.revoked?
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "webhook message and Telegram IDs are filtered from request logs" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(
      "message" => { "text" => "/start #{@group.telegram_join_token}" }, "chat_id" => 123456789012)
    assert_equal "[FILTERED]", filtered["message"]
    assert_equal "[FILTERED]", filtered["chat_id"]
  end

  private

  def webhook(secret: "webhook-test-secret", **changes)
    message = {
      text: "/start #{@group.telegram_join_token}",
      chat: { id: 123456789012, type: "private" },
      from: { id: 123456789012, is_bot: false, username: "Ada_123", first_name: "Ada", last_name: "Telegram" }
    }.merge(changes)
    post telegram_webhook_path, params: { update_id: 1, message: message },
      headers: { "X-Telegram-Bot-Api-Secret-Token" => secret }, as: :json
  end
end
