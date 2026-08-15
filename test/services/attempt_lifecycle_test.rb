require "test_helper"

class AttemptLifecycleTest < ActiveSupport::TestCase
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Timed", max_attempts: 2, time_limit_sec: 60, status: :published)
    @mcq = @exam.questions.create!(
      question_type: :mcq,
      prompt: "Capital?",
      points: 1,
      position: 0,
      config: {
        "options" => [
          { "id" => "a", "text" => "Paris", "is_correct" => true },
          { "id" => "b", "text" => "London", "is_correct" => false }
        ]
      }
    )
    @student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: @student)
  end

  test "start creates in-progress attempt with deadline" do
    attempt = AttemptLifecycle.start!(@assignment)
    assert attempt.in_progress?
    assert_equal 1, attempt.attempt_no
    assert attempt.deadline_at.present?
  end

  test "start resumes existing in-progress attempt" do
    first = AttemptLifecycle.start!(@assignment)
    second = AttemptLifecycle.start!(@assignment)
    assert_equal first.id, second.id
  end

  test "start blocked when revoked" do
    @assignment.revoke!
    assert_raises(AttemptLifecycle::NotAllowed) { AttemptLifecycle.start!(@assignment) }
  end

  test "start blocked when closed" do
    @exam.close!
    assert_raises(AttemptLifecycle::NotAllowed) { AttemptLifecycle.start!(@assignment) }
  end

  test "closing a test still lets an in-progress attempt resume" do
    attempt = AttemptLifecycle.start!(@assignment)
    @exam.close!

    resumed = AttemptLifecycle.start!(@assignment)
    assert_equal attempt.id, resumed.id
    assert resumed.in_progress?
  end

  test "max attempts enforced" do
    a1 = AttemptLifecycle.start!(@assignment)
    AttemptLifecycle.submit!(a1)
    a2 = AttemptLifecycle.start!(@assignment)
    AttemptLifecycle.submit!(a2)
    assert_raises(AttemptLifecycle::NotAllowed) { AttemptLifecycle.start!(@assignment) }
  end

  test "submit after deadline expires attempt" do
    attempt = AttemptLifecycle.start!(@assignment)
    attempt.update!(deadline_at: 1.minute.ago)
    assert_raises(AttemptLifecycle::Expired) { AttemptLifecycle.submit!(attempt) }
    assert attempt.reload.expired?
  end

  test "autosave loads exam questions once for a batch of answers" do
    other = @exam.questions.create!(
      question_type: :mcq,
      prompt: "Q2?",
      points: 1,
      position: 1,
      config: @mcq.config
    )
    attempt = Attempt.find(AttemptLifecycle.start!(@assignment).id)

    assert_queries_match(/FROM "questions"/, count: 1) do
      AttemptLifecycle.autosave!(attempt, [
        { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } },
        { "question_id" => other.id, "payload" => { "option_id" => "b" } }
      ])
    end
  end

  test "autosave and submit scores mcq" do
    attempt = AttemptLifecycle.start!(@assignment)
    AttemptLifecycle.autosave!(attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])
    AttemptLifecycle.submit!(attempt)
    assert attempt.reload.submitted?
    assert_equal 1, attempt.answers.find_by!(question: @mcq).auto_score.to_i
    assert attempt.grade.present?
  end

  test "autosave scores ordering and matching" do
    ordering = @exam.questions.create!(
      question_type: :ordering,
      prompt: "Order",
      points: 2,
      position: 1,
      config: {
        "items" => [
          { "id" => "e1", "text" => "First" },
          { "id" => "e2", "text" => "Second" },
          { "id" => "e3", "text" => "Third" }
        ]
      }
    )
    matching = @exam.questions.create!(
      question_type: :matching,
      prompt: "Match",
      points: 4,
      position: 2,
      config: {
        "left" => [ { "id" => "l1", "text" => "A" }, { "id" => "l2", "text" => "B" } ],
        "right" => [ { "id" => "r1", "text" => "1" }, { "id" => "r2", "text" => "2" } ],
        "pairs" => { "l1" => "r1", "l2" => "r2" }
      }
    )

    attempt = AttemptLifecycle.start!(@assignment)
    AttemptLifecycle.autosave!(attempt, [
      { "question_id" => ordering.id, "payload" => { "order" => %w[e1 e2 e3] } },
      { "question_id" => matching.id, "payload" => { "pairs" => { "l1" => "r1", "l2" => "r9" } } }
    ])

    assert_equal 2, attempt.answers.find_by!(question: ordering).auto_score.to_i
    assert_equal 2, attempt.answers.find_by!(question: matching).auto_score.to_i
  end

  test "start broadcasts live board" do
    assert_turbo_stream_broadcasts [ @exam, :live_board ] do
      AttemptLifecycle.start!(@assignment)
    end
  end

  test "autosave broadcasts grade live but not live board" do
    attempt = AttemptLifecycle.start!(@assignment)

    assert_turbo_stream_broadcasts [ attempt, :grade_live ] do
      AttemptLifecycle.autosave!(attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])
    end

    board_streams = capture_turbo_stream_broadcasts [ @exam, :live_board ] do
      AttemptLifecycle.autosave!(attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "b" } } ])
    end
    assert_empty board_streams
  end

  test "submit broadcasts grade live and live board" do
    attempt = AttemptLifecycle.start!(@assignment)
    AttemptLifecycle.autosave!(attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])

    assert_turbo_stream_broadcasts [ attempt, :grade_live ] do
      AttemptLifecycle.submit!(attempt)
    end
    assert attempt.reload.submitted?
  end

  test "submit broadcasts live board" do
    attempt = AttemptLifecycle.start!(@assignment)

    assert_turbo_stream_broadcasts [ @exam, :live_board ] do
      AttemptLifecycle.submit!(attempt)
    end
  end

  test "expire broadcasts grade live and live board" do
    attempt = AttemptLifecycle.start!(@assignment)
    attempt.update!(deadline_at: 1.minute.ago)

    assert_turbo_stream_broadcasts [ attempt, :grade_live ] do
      AttemptLifecycle.expire_if_needed!(attempt)
    end
    assert attempt.reload.expired?

    attempt = AttemptLifecycle.start!(@assignment)
    attempt.update!(deadline_at: 1.minute.ago)
    assert_turbo_stream_broadcasts [ @exam, :live_board ] do
      AttemptLifecycle.expire_if_needed!(attempt)
    end
  end

  test "autosave broadcasts only the questions it wrote" do
    untouched = @exam.questions.create!(question_type: :short_text, prompt: "Q2?", points: 1, position: 1, config: {})
    attempt = AttemptLifecycle.start!(@assignment)

    streams = capture_turbo_stream_broadcasts [ attempt, :grade_live ] do
      AttemptLifecycle.autosave!(attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])
    end

    assert_equal [ ActionView::RecordIdentifier.dom_id(@mcq, :student_answer) ], streams.map { |s| s["target"] },
      "an untouched question (#{untouched.id}) must not be rebroadcast"
  end

  test "expiring a scope refreshes the board once rather than once per attempt" do
    attempts = 3.times.map do |i|
      assignment = @exam.assignments.create!(student: @teacher.students.create!(name: "S#{i}"))
      AttemptLifecycle.start!(assignment).tap { |a| a.update!(deadline_at: 1.minute.ago) }
    end

    streams = capture_turbo_stream_broadcasts [ @exam, :live_board ] do
      AttemptLifecycle.expire_overdue!(Attempt.where(id: attempts.map(&:id)))
    end

    assert_equal [ "live_board" ], streams.map { |s| s["target"] }
    assert attempts.all? { |attempt| attempt.reload.expired? }, "every attempt must still expire"
  end

  test "expiring an attempt with no answers pushes the header only" do
    @exam.questions.create!(question_type: :short_text, prompt: "Q2?", points: 1, position: 1, config: {})
    attempt = AttemptLifecycle.start!(@assignment)
    attempt.update!(deadline_at: 1.minute.ago)

    streams = capture_turbo_stream_broadcasts [ attempt, :grade_live ] do
      AttemptLifecycle.expire_if_needed!(attempt)
    end

    assert_equal [ "attempt_live_header" ], streams.map { |s| s["target"] }
  end

  test "no-op expire does not broadcast" do
    attempt = AttemptLifecycle.start!(@assignment)

    grade_streams = capture_turbo_stream_broadcasts [ attempt, :grade_live ] do
      AttemptLifecycle.expire_if_needed!(attempt)
    end
    board_streams = capture_turbo_stream_broadcasts [ @exam, :live_board ] do
      AttemptLifecycle.expire_if_needed!(attempt)
    end

    assert_empty grade_streams
    assert_empty board_streams
  end
end
