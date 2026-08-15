require "test_helper"

class AssignmentTest < ActiveSupport::TestCase
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", max_attempts: 2, status: :published)
    @student = @teacher.students.create!(name: "Ada")
    @assignment = @exam.assignments.create!(student: @student)
  end

  test "attempts_used and in_progress_attempt use preloaded attempts" do
    now = Time.current
    @assignment.attempts.create!(
      attempt_no: 1, status: :submitted, started_at: now, last_activity_at: now, submitted_at: now
    )
    in_progress = @assignment.attempts.create!(
      attempt_no: 2, status: :in_progress, started_at: now, last_activity_at: now
    )

    loaded = Assignment.preload(:attempts).find(@assignment.id)

    assert_no_queries do
      assert_equal 2, loaded.attempts_used
      assert_equal in_progress.id, loaded.in_progress_attempt.id
      assert_equal in_progress.id, loaded.latest_attempt.id
    end
  end
end
