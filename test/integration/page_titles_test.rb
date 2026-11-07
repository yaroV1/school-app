require "test_helper"

class PageTitlesTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @group = @teacher.class_groups.create!(name: "10-A")
    @subject = @group.subjects.create!(name: "Алгебра")
    @student = @teacher.students.create!(name: "Ada Lovelace")
    @group.add_student!(@student)
    @exam = create_exam!(@teacher, title: "Контрольна", status: :published, subject: @subject)
    @exam.questions.create!(question_type: :short_text, prompt: "Q?", points: 1, position: 0, config: {})
    @assignment = @exam.assignments.create!(student: @student)
  end

  test "every page names the record first, then where you are, then the app" do
    {
      class_groups_path => titled(I18n.t("classes.index.title")),
      new_class_group_path => titled(I18n.t("classes.new.title")),
      class_group_path(@group) => titled(@group.name, I18n.t("classes.show.subjects")),
      students_class_group_path(@group) => titled(@group.name, I18n.t("classes.show.students")),
      edit_class_group_path(@group) => titled(@group.name, I18n.t("classes.edit.title")),
      subject_path(@subject) => titled(@subject.name, @group.name),
      stats_subject_path(@subject) => titled(@subject.name, I18n.t("subjects.show.stats"), @group.name),
      edit_subject_path(@subject) => titled(@subject.name, I18n.t("subjects.edit.title")),
      new_subject_exam_path(@subject) => titled(I18n.t("exams.new.title"), @subject.name),
      test_path(@exam) => titled(@exam.title, @subject.name),
      edit_test_path(@exam) => titled(@exam.title, I18n.t("exams.show.edit_settings")),
      manage_test_assignments_path(@exam) => titled(@exam.title, I18n.t("exams.show.assign")),
      print_test_path(@exam) => titled(@exam.title, I18n.t("exams.show.print")),
      print_key_test_path(@exam) => titled(@exam.title, I18n.t("exams.print_key.heading")),
      live_test_path(@exam) => titled(@exam.title, I18n.t("exams.show.live_board")),
      results_test_path(@exam) => titled(@exam.title, I18n.t("exams.show.results")),
      duplicate_test_path(@exam) => titled(@exam.title, I18n.t("exams.show.duplicate")),
      student_path(@student) => titled(@student.name, @group.name),
      edit_student_path(@student) => titled(@student.name, I18n.t("students.edit.title")),
      new_session_path => titled(I18n.t("auth.sign_in")),
      new_password_path => titled(I18n.t("auth.passwords.forgot_title")),
      edit_password_path(@teacher.password_reset_token) => titled(I18n.t("auth.passwords.update_title"))
    }.each do |path, expected|
      get path
      assert_response :success, path
      assert_select "title", expected
    end

    get student_portal_path(token: @assignment.access_token)
    assert_response :success
    assert_select "title", titled(@exam.title, @subject.name)

    post student_start_path(token: @assignment.access_token)
    get student_run_path(token: @assignment.access_token)
    assert_response :success
    assert_select "title", titled(@exam.title, @subject.name)

    AttemptLifecycle.submit!(@assignment.attempts.last)
    get student_done_path(token: @assignment.access_token)
    assert_response :success
    assert_select "title", titled(@exam.title, I18n.t("take.done_title"))

    attempt = @assignment.attempts.last
    get attempt_path(attempt)
    assert_response :success
    assert_select "title", titled(@student.name, I18n.t("exams.results.grade"), @exam.title)

    get report_attempt_path(attempt)
    assert_response :success
    assert_select "title", titled(@student.name, I18n.t("attempts.show.report"), @exam.title)
  end

  test "a student with no class is named without an empty section" do
    loner = @teacher.students.create!(name: "Solo")

    get student_path(loner)
    assert_response :success
    assert_select "title", titled(loner.name)
  end

  test "a record name cannot close the title element" do
    @group.update!(name: "7</title>")

    get class_group_path(@group)
    assert_response :success
    assert_select "title", titled("7</title>", I18n.t("classes.show.subjects"))
  end

  private

  def titled(*parts)
    ApplicationController.helpers.title_parts(*parts, I18n.t("app_name"))
  end
end
