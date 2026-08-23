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

  test "a fired grade stamps a solid seal and a draft grade stays wet" do
    fired = Grade.new(max_score: 10, total_score: 8, finalized_by_teacher: true)
    wet = Grade.new(max_score: 10, total_score: 3.5, finalized_by_teacher: false)

    stamped = Nokogiri::HTML5.fragment(score_seal(fired))
    seal = stamped.at_css(".seal")

    assert_includes seal["class"], "seal-fired"
    refute_includes seal["class"], "seal-lg"
    assert_equal "8", seal.at_css(".seal-score").text
    assert_equal "10", seal.at_css(".seal-max").text
    assert_equal I18n.t("common.score_seal_fired", score: "8", max: "10"), seal["aria-label"]

    draft = Nokogiri::HTML5.fragment(score_seal(wet, size: :lg))
    wet_seal = draft.at_css(".seal")

    assert_includes wet_seal["class"], "seal-wet"
    assert_includes wet_seal["class"], "seal-lg"
    assert_equal "3.5", wet_seal.at_css(".seal-score").text
    assert_equal I18n.t("common.score_seal_wet", score: "3.5", max: "10"), wet_seal["aria-label"]
  end

  test "a missing grade is a dash, not an empty stamp" do
    html = Nokogiri::HTML5.fragment(score_seal(nil))

    assert_nil html.at_css(".seal")
    assert_equal I18n.t("common.dash"), html.text.strip
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
