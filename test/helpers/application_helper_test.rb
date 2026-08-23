require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  ICON_PARTIAL = Rails.root.join("app/views/shared/_icon.html.erb")

  # Reading the branches out of the partial rather than listing them here means a new
  # icon is covered the moment it is drawn, and a deleted one cannot leave a stale name
  # passing behind it.
  test "every icon the partial names draws something" do
    names = icon_names

    assert_operator names.size, :>=, 9, "the app's icon set should not have shrunk silently"

    names.each do |name|
      svg = Nokogiri::HTML5.fragment(ui_icon(name))

      assert svg.css("svg path").any?, "the #{name} icon renders an svg with nothing drawn in it"
    end
  end

  test "an icon name with no branch raises instead of rendering an empty svg" do
    # Rails wraps anything raised inside a template, so the ArgumentError arrives as the cause.
    error = assert_raises(ActionView::Template::Error) { ui_icon("no-such-icon") }

    assert_instance_of ArgumentError, error.cause
    assert_match "no-such-icon", error.message
  end

  test "take_brief names the student, the count, the time and the attempt" do
    teacher = users(:one)
    exam = create_exam!(teacher, title: "Unit", time_limit_sec: 300, max_attempts: 2)
    exam.questions.create!(question_type: :short_text, prompt: "Sky?", points: 1, position: 0, config: {})
    student = teacher.students.create!(name: "Sam")

    assert_equal I18n.t("take.brief",
      name: "Sam",
      questions: I18n.t("exams.questions_count", count: 1),
      time: I18n.t("take.brief_time", count: 5),
      used: 0,
      max: 2), take_brief(exam, student, 0)
  end

  test "take_brief says untimed when there is no clock" do
    teacher = users(:one)
    exam = create_exam!(teacher, title: "Unit")
    student = teacher.students.create!(name: "Sam")

    assert_includes take_brief(exam, student, 1), I18n.t("take.brief_untimed")
  end

  test "answer_started? follows each question type's payload" do
    assert_not answer_started?(Question.new(question_type: :mcq), nil)
    assert_not answer_started?(Question.new(question_type: :mcq), Answer.new(payload: {}))
    assert answer_started?(Question.new(question_type: :mcq), Answer.new(payload: { "option_id" => "a" }))

    assert_not answer_started?(Question.new(question_type: :ordering), Answer.new(payload: { "order" => [] }))
    assert answer_started?(Question.new(question_type: :ordering), Answer.new(payload: { "order" => [ "e1" ] }))

    assert_not answer_started?(Question.new(question_type: :matching), Answer.new(payload: { "pairs" => { "l1" => "" } }))
    assert answer_started?(Question.new(question_type: :matching), Answer.new(payload: { "pairs" => { "l1" => "r2" } }))

    assert_not answer_started?(Question.new(question_type: :open), Answer.new(payload: { "text" => "  " }))
    assert answer_started?(Question.new(question_type: :open), Answer.new(payload: { "text" => "x" }))
  end

  private

  def icon_names
    ICON_PARTIAL.read.scan(/when "([a-z_]+)"/).flatten
  end
end
