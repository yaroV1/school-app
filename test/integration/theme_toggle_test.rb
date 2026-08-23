require "test_helper"

class ThemeToggleTest < ActionDispatch::IntegrationTest
  test "signed-in chrome exposes a theme toggle and a boot script" do
    sign_in_as users(:one)
    get class_groups_path
    assert_response :success
    assert_select "button[data-controller='theme']"
    assert_match(/localStorage\.getItem\(key\)/, response.body)
  end

  test "the sign-in page still offers the toggle without a session" do
    get new_session_path
    assert_response :success
    assert_select "button[data-controller='theme']"
  end

  test "a student taking a test can switch theme without an account" do
    teacher = users(:one)
    exam = create_exam!(teacher, title: "Theme", status: :published)
    exam.questions.create!(question_type: :short_text, prompt: "Sky?", points: 1, position: 0, config: {})
    student = teacher.students.create!(name: "Nia")
    assignment = exam.assignments.create!(student: student)

    get student_portal_url(token: assignment.access_token)
    assert_response :success
    assert_select "button[data-controller='theme']"
  end
end
