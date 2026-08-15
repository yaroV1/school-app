require "test_helper"

class ExamTabsTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @group = @teacher.class_groups.create!(name: "10-A")
    @exam = create_exam!(@teacher, title: "Контрольна", status: :published, class_group: @group)
    @exam.questions.create!(question_type: :short_text, prompt: "Q?", points: 1, position: 0, config: {})
  end

  test "each test page highlights its own tab" do
    {
      test_path(@exam) => t("exams.show.overview"),
      edit_test_path(@exam) => t("exams.show.edit_settings"),
      manage_test_assignments_path(@exam) => t("exams.show.assign"),
      live_test_path(@exam) => t("exams.show.live_board"),
      results_test_path(@exam) => t("exams.show.results")
    }.each do |path, expected|
      get path
      assert_response :success
      assert_equal [ expected ], active_tabs, "wrong active tab on #{path}"
    end
  end

  test "the live board tab is not highlighted while on the test page" do
    get test_path(@exam)
    assert_response :success
    assert_select "nav a[href=?]", live_test_path(@exam) do |links|
      assert_no_match(/border-slate-900/, links.first["class"])
    end
  end

  test "the filter query on a tab does not break highlighting" do
    get results_test_path(@exam)
    assert_equal [ t("exams.show.results") ], active_tabs
  end

  test "closing asks for confirmation" do
    get test_path(@exam)
    assert_select "form[action=?][data-turbo-confirm=?]",
      close_test_path(@exam), t("exams.show.close_confirm")
  end

  test "publishing asks for confirmation" do
    draft = create_exam!(@teacher, title: "Чернетка", status: :draft, class_group: @group)
    get test_path(draft)
    assert_select "form[action=?][data-turbo-confirm=?]",
      publish_test_path(draft), t("exams.show.publish_confirm")
  end

  test "the state action sits outside the tab bar" do
    get test_path(@exam)
    assert_select "nav form", false, "state actions must not live in the tab nav"
    assert_select "form[action=?]", close_test_path(@exam)
  end

  test "a draft hides the tabs that have nothing to show yet" do
    draft = create_exam!(@teacher, title: "Чернетка", status: :draft, class_group: @group)
    get test_path(draft)

    assert_select "nav a[href=?]", test_path(draft)
    assert_select "nav a[href=?]", manage_test_assignments_path(draft)
    assert_select "nav a[href=?]", live_test_path(draft), false
    assert_select "nav a[href=?]", results_test_path(draft), false
  end

  test "a closed test offers no state action" do
    @exam.close!
    get test_path(@exam)
    assert_select "form[action=?]", close_test_path(@exam), false
    assert_select "form[action=?]", publish_test_path(@exam), false
  end

  private

  def active_tabs
    css_select("nav a").select { |a| a["class"].to_s.include?("border-slate-900") }.map { |a| a.text.strip }
  end

  def t(key)
    I18n.t(key)
  end
end
