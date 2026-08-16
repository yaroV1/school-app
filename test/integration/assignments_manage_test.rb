require "test_helper"

class AssignmentsManageTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher

    @group = @teacher.class_groups.create!(name: "Group 1")
    @exam = create_exam!(@teacher, title: "Quiz", status: :published, class_group: @group)
    @student = @teacher.students.create!(name: "Ada")
    @group.replace_members!([ @student.id ])
    @assignment = @exam.assignments.create!(student: @student)
  end

  test "manage page keeps row actions outside the bulk revoke form" do
    get manage_test_assignments_path(@exam)
    assert_response :success

    assert_select "form#bulk-revoke"
    assert_select "form#bulk-revoke table", false
    assert_select "form#bulk-revoke form", false
    assert_select "tr##{dom_id(@assignment)} input[name='assignment_ids[]'][form=bulk-revoke]"
    assert_select "form[action=?]", revoke_assignment_path(@assignment)
    assert_select "form[action=?]", regenerate_token_assignment_path(@assignment)
  end

  test "revoke replaces the row via turbo stream" do
    post revoke_assignment_path(@assignment), as: :turbo_stream

    assert @assignment.reload.revoked?
    assert_turbo_stream action: :replace, target: dom_id(@assignment)
    assert_select "turbo-stream[action=replace][target=?]", dom_id(@assignment) do
      assert_select "td", text: I18n.t("statuses.revoked")
      assert_select "form[action=?]", revoke_assignment_path(@assignment), false
      assert_select "input[name='assignment_ids[]']", false
      assert_select "form[action=?]", regenerate_token_assignment_path(@assignment)
    end
  end

  test "regenerate replaces the row via turbo stream with the new token" do
    old_token = @assignment.access_token

    post regenerate_token_assignment_path(@assignment), as: :turbo_stream

    @assignment.reload
    assert_not_equal old_token, @assignment.access_token
    assert_not @assignment.revoked?
    assert_turbo_stream action: :replace, target: dom_id(@assignment)
    assert_includes response.body, @assignment.access_token
    assert_not_includes response.body, old_token
    assert_select "turbo-stream[action=replace][target=?]", dom_id(@assignment) do
      assert_select "td", text: I18n.t("statuses.active")
      assert_select "form[action=?]", revoke_assignment_path(@assignment)
    end
  end

  test "html revoke still redirects to the manage page" do
    post revoke_assignment_path(@assignment), as: :html

    assert @assignment.reload.revoked?
    assert_redirected_to manage_test_assignments_path(@exam)
    follow_redirect!
    assert_match I18n.t("exams.flash.revoked"), response.body
  end

  test "html regenerate still redirects to the manage page" do
    post regenerate_token_assignment_path(@assignment), as: :html

    assert_redirected_to manage_test_assignments_path(@exam)
    follow_redirect!
    assert_match I18n.t("exams.flash.regenerated"), response.body
  end

  private

  def dom_id(record)
    ActionView::RecordIdentifier.dom_id(record)
  end
end
