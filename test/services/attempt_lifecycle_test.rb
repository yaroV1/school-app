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
end
