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
      results_test_path(@exam) => t("exams.show.results"),
      print_test_path(@exam) => t("exams.show.print")
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
      assert_nil links.first["aria-current"]
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

  test "the print tab is offered in every state, unlike the live board and results" do
    %i[draft published closed].each do |status|
      @exam.update_column(:status, Exam.statuses[status])

      get test_path(@exam)
      assert_response :success
      assert_select "nav a[href=?]", print_test_path(@exam), 1,
                    "the paper copy must be reachable while a test is #{status}"
    end
  end

  test "the paper copy and the answer key link to each other, out of the printer" do
    get print_test_path(@exam)
    assert_response :success
    assert_select ".no-print a[href=?]", print_key_test_path(@exam)

    get print_key_test_path(@exam)
    assert_response :success
    # Pinned to the link's own label: the Друк tab is also inside this page's .no-print
    # chrome and also points at print_test_path, so an href-only assertion is satisfied by
    # the tab bar and proves nothing about the back-link.
    assert_select ".no-print a[href=?]", print_test_path(@exam),
                  text: t("exams.print_key.sheet_link")
  end

  private

  def active_tabs
    css_select("nav a[aria-current='page']").map { |a| a.text.strip }
  end

  def t(key)
    I18n.t(key)
  end
end
