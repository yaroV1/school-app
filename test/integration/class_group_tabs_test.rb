require "test_helper"

class ClassGroupTabsTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @group = @teacher.class_groups.create!(name: "10-A")
    @group.subjects.create!(name: "Алгебра")
    @student = @teacher.students.create!(name: "Ada Lovelace")
    @group.add_student!(@student)
  end

  test "subjects tab is the default and keeps the roster off the page" do
    get class_group_path(@group)
    assert_response :success
    assert_match "Алгебра", response.body
    assert_no_match(/Ada Lovelace/, response.body)
  end

  test "students tab lists the roster" do
    get students_class_group_path(@group)
    assert_response :success
    assert_match "Ada Lovelace", response.body
  end

  test "a failed student create re-renders the students tab with the error" do
    post class_group_students_path(@group), params: { student: { name: "" } }
    assert_response :unprocessable_entity
    assert_match "Ada Lovelace", response.body
    assert_select "form[action=?]", class_group_students_path(@group)
  end

  test "a failed subject create re-renders the subjects tab with the error" do
    post class_group_subjects_path(@group), params: { subject: { name: "" } }
    assert_response :unprocessable_entity
    assert_match "Алгебра", response.body
    assert_select "form[action=?]", class_group_subjects_path(@group)
  end

  test "adding a student lands back on the students tab" do
    post class_group_students_path(@group), params: { student: { name: "Alan Turing" } }
    assert_redirected_to students_class_group_path(@group)
    follow_redirect!
    assert_match "Alan Turing", response.body
  end

  test "removing a member lands back on the students tab" do
    delete remove_member_class_group_path(@group, student_id: @student.id)
    assert_redirected_to students_class_group_path(@group)
    assert_empty @group.reload.students
  end

  test "tabs are scoped to the signed-in teacher" do
    other = User.create!(email_address: "other@example.com", password: "password123")
    foreign = other.class_groups.create!(name: "Not mine")

    get students_class_group_path(foreign)
    assert_response :not_found
  end
end
