require "test_helper"

class LiveBoardTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher

    @group = @teacher.class_groups.create!(name: "Group 1")
    @exam = create_exam!(@teacher, title: "Live Quiz", status: :published, class_group: @group)
    @exam.questions.create!(
      question_type: :short_text,
      prompt: "Name?",
      points: 1,
      position: 0,
      config: {}
    )
    @in_group = @teacher.students.create!(name: "In Group")
    @out_group = @teacher.students.create!(name: "Out Group")
    @group.replace_members!([ @in_group.id ])
    @exam.assignments.create!(student: @in_group)
    @exam.assignments.create!(student: @out_group)
  end

  test "live board page loads and frame shows assignments" do
    get live_test_path(@exam)
    assert_response :success
    assert_match I18n.t("exams.live.title_prefix"), response.body
    assert_select "turbo-cable-stream-source"

    get live_test_path(@exam), headers: { "Turbo-Frame" => "live_board" }
    assert_response :success
    assert_match(/In Group/, response.body)
    assert_match(/Out Group/, response.body)
    assert_match I18n.t("statuses.not_started"), response.body
  end

  test "revoke broadcasts live board" do
    assignment = @exam.assignments.find_by!(student: @in_group)
    assert_turbo_stream_broadcasts [ @exam, :live_board ] do
      post revoke_assignment_path(assignment)
    end
  end

  test "bulk revoke revokes selected assignments" do
    ids = @exam.assignments.pluck(:id)
    post bulk_revoke_test_assignments_path(@exam), params: { assignment_ids: ids }
    assert_redirected_to manage_test_assignments_path(@exam)
    assert @exam.assignments.reload.all?(&:revoked?)
  end

  test "live board expires overdue attempts of the watched test only" do
    other_exam = create_exam!(@teacher, title: "Other Quiz", status: :published, class_group: @group)
    watched = overdue_attempt_for(@exam)
    untouched = overdue_attempt_for(other_exam)

    get live_test_path(@exam), headers: { "Turbo-Frame" => "live_board" }
    assert_response :success

    assert watched.reload.expired?
    assert untouched.reload.in_progress?
  end

  private

  def overdue_attempt_for(exam)
    assignment = exam.assignments.find_or_create_by!(student: @in_group)
    started = 1.hour.ago
    assignment.attempts.create!(
      attempt_no: assignment.attempts.count + 1,
      status: :in_progress,
      started_at: started,
      last_activity_at: started,
      deadline_at: 1.minute.ago
    )
  end
end
