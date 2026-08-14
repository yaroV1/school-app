require "test_helper"

class Phase11Test < ActiveSupport::TestCase
  setup do
    @teacher = users(:one)
    @exam = @teacher.exams.create!(title: "Windowed", max_attempts: 2, time_limit_sec: 120, status: :published)
    @mcq = @exam.questions.create!(
      question_type: :mcq,
      prompt: "Q?",
      points: 1,
      position: 0,
      config: {
        "options" => [
          { "id" => "a", "text" => "A", "is_correct" => true },
          { "id" => "b", "text" => "B", "is_correct" => false }
        ]
      }
    )
    @student = @teacher.students.create!(name: "Pat")
    @assignment = @exam.assignments.create!(student: @student)
  end

  test "available_from blocks new starts" do
    @exam.update!(available_from: 1.hour.from_now)
    error = assert_raises(AttemptLifecycle::NotAllowed) { AttemptLifecycle.start!(@assignment) }
    assert_equal I18n.t("take.errors.not_available_yet"), error.message
  end

  test "available_until blocks new starts" do
    @exam.update!(available_until: 1.hour.ago)
    error = assert_raises(AttemptLifecycle::NotAllowed) { AttemptLifecycle.start!(@assignment) }
    assert_equal I18n.t("take.errors.no_longer_available"), error.message
  end

  test "in-progress attempt can resume after availability window ends" do
    attempt = AttemptLifecycle.start!(@assignment)
    @exam.update!(available_until: 1.minute.ago)
    resumed = AttemptLifecycle.start!(@assignment)
    assert_equal attempt.id, resumed.id
    assert resumed.in_progress?
  end

  test "autosave persists answers and bumps lock_version" do
    attempt = AttemptLifecycle.start!(@assignment)
    version = attempt.lock_version

    AttemptLifecycle.autosave!(
      attempt,
      [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ],
      expected_version: version
    )

    attempt.reload
    assert_operator attempt.lock_version, :>, version
    assert_equal "a", attempt.answers.find_by!(question: @mcq).option_id
  end

  test "stale lock_version still saves answers last-write-wins" do
    attempt = AttemptLifecycle.start!(@assignment)
    AttemptLifecycle.autosave!(
      attempt,
      [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ],
      expected_version: attempt.lock_version
    )
    stale = attempt.lock_version - 1

    AttemptLifecycle.autosave!(
      attempt.reload,
      [ { "question_id" => @mcq.id, "payload" => { "option_id" => "b" } } ],
      expected_version: stale
    )

    assert_equal "b", attempt.reload.answers.find_by!(question: @mcq).option_id
  end

  test "expire overdue job marks attempt expired and gradable" do
    attempt = AttemptLifecycle.start!(@assignment)
    AttemptLifecycle.autosave!(
      attempt,
      [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ]
    )
    attempt.update_columns(deadline_at: 1.minute.ago)

    ExpireOverdueAttemptsJob.perform_now
    attempt.reload

    assert attempt.expired?
    assert attempt.grade.present?
    assert_equal 1, attempt.answers.find_by!(question: @mcq).auto_score.to_i
  end

  test "board_status sorts in progress first" do
    other = @teacher.students.create!(name: "Zoe")
    a2 = @exam.assignments.create!(student: other)
    AttemptLifecycle.start!(@assignment)
    AttemptLifecycle.submit!(AttemptLifecycle.start!(a2))

    statuses = @exam.assignments.includes(:student, :attempts).map(&:board_status)
    assert_includes statuses, "in_progress"
    assert_includes statuses, "submitted"
    assert_equal 0, Assignment::BOARD_SORT["in_progress"]
    assert_operator Assignment::BOARD_SORT["in_progress"], :<, Assignment::BOARD_SORT["submitted"]
  end
end
