require "test_helper"

class LiveBroadcastTest < ActiveSupport::TestCase
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", status: :published, time_limit_sec: 600)
    @mcq = @exam.questions.create!(
      question_type: :mcq, prompt: "Capital?", points: 1, position: 0,
      config: { "options" => [
        { "id" => "a", "text" => "Paris", "is_correct" => true },
        { "id" => "b", "text" => "London", "is_correct" => false }
      ] }
    )
    @student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: @student)
  end

  test "a broadcast failure does not fail the student's save" do
    attempt = AttemptLifecycle.start!(@assignment)

    with_broken_cable do
      assert_nothing_raised do
        AttemptLifecycle.autosave!(attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])
      end
    end

    assert_equal "a", attempt.answers.sole.reload.option_id, "the answer must still be persisted"
  end

  test "a broadcast failure does not fail the student's submit" do
    attempt = AttemptLifecycle.start!(@assignment)

    with_broken_cable do
      assert_nothing_raised { AttemptLifecycle.submit!(attempt) }
    end

    assert attempt.reload.submitted?, "the attempt must still be submitted"
  end

  test "a broadcast failure does not fail starting an attempt" do
    with_broken_cable do
      assert_nothing_raised { AttemptLifecycle.start!(@assignment) }
    end

    assert @assignment.attempts.sole.in_progress?
  end

  test "submitting with final answers broadcasts them once, not once per save" do
    attempt = AttemptLifecycle.start!(@assignment)
    answers = [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ]

    streams = capture_turbo_stream_broadcasts [ attempt, :grade_live ] do
      AttemptLifecycle.submit!(attempt, answers: answers)
    end

    targets = streams.map { |s| s["target"] }
    assert_equal targets.uniq, targets, "no target should be pushed twice in one submit"
    assert_includes targets, "attempt_live_header"
    assert_includes targets, ActionView::RecordIdentifier.dom_id(@mcq, :student_answer)
    assert_equal "a", attempt.answers.sole.reload.option_id
  end

  test "the board snapshot stays inside the exam's own assignments" do
    other_teacher = User.create!(email_address: "other@example.com", password: "password123")
    other_exam = create_exam!(other_teacher, title: "Theirs", status: :published)
    other_exam.assignments.create!(student: other_teacher.students.create!(name: "Not mine"))
    @assignment # ours

    snapshot = LiveBoard.snapshot(@exam)
    assert_equal [ @assignment.id ], snapshot[:assignments].map(&:id)
  end

  private

  def with_broken_cable
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to) { |*, **| raise "cable is down" }
    yield
  ensure
    Turbo::StreamsChannel.singleton_class.remove_method(:broadcast_replace_to)
  end
end
