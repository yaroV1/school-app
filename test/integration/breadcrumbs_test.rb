require "test_helper"

class BreadcrumbsTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @group = @teacher.class_groups.create!(name: "10-A")
    @subject = @group.subjects.create!(name: "Алгебра")
    @student = @teacher.students.create!(name: "Ada Lovelace")
    @group.add_student!(@student)
  end

  test "every trail starts at the class index" do
    exam = create_exam!(@teacher, title: "Контрольна", status: :published, subject: @subject)
    exam.questions.create!(question_type: :short_text, prompt: "Q?", points: 1, position: 0, config: {})
    assignment = exam.assignments.create!(student: @student)
    post student_start_url(token: assignment.access_token)
    attempt = assignment.attempts.last
    AttemptLifecycle.submit!(attempt)

    [ class_group_path(@group), subject_path(@subject), test_path(exam),
      student_path(@student), edit_student_path(@student), attempt_path(attempt) ].each do |path|
      get path
      assert_response :success
      assert_equal I18n.t("classes.index.title"), crumbs.first, "wrong first crumb on #{path}"
    end
  end

  test "editing a student keeps the class group its own page shows" do
    get edit_student_path(@student)
    assert_response :success
    assert_equal [ I18n.t("classes.index.title"), @group.name, @student.name, I18n.t("students.edit.title") ], crumbs
  end

  test "a student with no class group still gets a trail" do
    loner = @teacher.students.create!(name: "Solo")

    get edit_student_path(loner)
    assert_response :success
    assert_equal [ I18n.t("classes.index.title"), "Solo", I18n.t("students.edit.title") ], crumbs
  end

  private

  def crumbs
    css_select("nav.breadcrumbs > *").reject { |el| el["class"].to_s.include?("breadcrumb-sep") }.map { |el| el.text.strip }
  end
end
