require "test_helper"

# The student run page is the answer-key boundary: it calls the Question student-facing
# readers directly, and nothing sits between it and the response. These tests render the
# real page as an unauthenticated student and assert the keys never reach the body.
#
# Sentinel strings rather than realistic copy, so a match cannot be a coincidence.
class AnswerKeyLeakTest < ActionDispatch::IntegrationTest
  RUBRIC       = "SENTINEL_RUBRIC_DO_NOT_LEAK".freeze
  MODEL_ANSWER = "SENTINEL_MODEL_ANSWER_DO_NOT_LEAK".freeze

  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", status: :published)

    @mcq = @exam.questions.create!(
      question_type: :mcq, prompt: "Capital?", points: 1, position: 0,
      config: { "options" => [
        { "id" => "a", "text" => "Paris", "is_correct" => false },
        { "id" => "b", "text" => "Kyiv", "is_correct" => true }
      ] }
    )
    @ordering = @exam.questions.create!(
      question_type: :ordering, prompt: "Order these", points: 1, position: 1,
      config: { "items" => [
        { "id" => "e1", "text" => "First" },
        { "id" => "e2", "text" => "Second" },
        { "id" => "e3", "text" => "Third" },
        { "id" => "e4", "text" => "Fourth" }
      ] }
    )
    @matching = @exam.questions.create!(
      question_type: :matching, prompt: "Match these", points: 1, position: 2,
      config: {
        "left" => [ { "id" => "l1", "text" => "Alpha" }, { "id" => "l2", "text" => "Beta" } ],
        "right" => [ { "id" => "r1", "text" => "One" }, { "id" => "r2", "text" => "Two" } ],
        "pairs" => { "l1" => "r2", "l2" => "r1" }
      }
    )
    @source = @exam.questions.create!(
      question_type: :source, prompt: "Summarize", points: 2, position: 3,
      config: { "source" => "A short passage.", "rubric" => RUBRIC }
    )
    @open = @exam.questions.create!(
      question_type: :open, prompt: "Explain", points: 2, position: 4,
      config: { "model_answer" => MODEL_ANSWER }
    )

    student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: student)
    @attempt = AttemptLifecycle.start!(@assignment)
    @token = @assignment.access_token
  end

  test "the student run page carries no answer key" do
    get student_run_url(token: @token)
    assert_response :success
    body = response.body

    # The visible content students need is present, so a body that merely failed to render
    # cannot pass these assertions.
    assert_match "Kyiv", body
    assert_match "A short passage.", body
    assert_match "Alpha", body

    assert_no_answer_key body
  end

  test "ordering items render in the seeded shuffle, not the stored answer order" do
    expected = @ordering.display_items_for(nil, @attempt.id).map { |item| item["id"] }

    # Guard: if the seeded shuffle ever coincides with the stored order this test proves
    # nothing, so fail loudly here rather than pass vacuously.
    refute_equal @ordering.correct_order_ids, expected,
                 "fixture seed now shuffles to the stored order — change the items or the fixture"

    get student_run_url(token: @token)
    assert_response :success

    rendered = css_select("input[name='answers[#{@ordering.id}][order][]']").map { |el| el["value"] }
    assert_equal expected, rendered,
                 "ordering items did not render through display_items_for"
  end

  test "a revoked link cannot reach the run page at all" do
    @assignment.update!(revoked_at: Time.current)

    get student_run_url(token: @token)
    refute_match(/is_correct/, response.body)
    refute_match RUBRIC, response.body
  end

  # A wording fix is the one teacher edit that rewrites a live question, and for source
  # and matching it rewrites the very hash the key sits in.
  test "a corrected question still hides its key from the student" do
    sign_in_as @teacher
    patch test_question_path(@exam, @mcq), params: {
      question: { prompt: "Which capital?", texts: { "b" => "Kyiv, corrected" } }
    }
    assert_equal I18n.t("exams.flash.question_updated"), flash[:notice]
    patch test_question_path(@exam, @source), params: {
      question: { source: "A corrected passage." }
    }
    patch test_question_path(@exam, @matching), params: {
      question: { texts: { "l1" => "Alpha, corrected" } }
    }
    patch test_question_path(@exam, @open), params: {
      question: { prompt: "Explain, corrected" }
    }
    sign_out

    get student_run_url(token: @token)
    assert_response :success
    body = response.body

    assert_match "Which capital?", body
    assert_match "Kyiv, corrected", body
    assert_match "A corrected passage.", body
    assert_match "Alpha, corrected", body
    assert_match "Explain, corrected", body

    assert_no_answer_key body
  end

  test "a wording fix does not reshuffle an ordering question under the student" do
    before = rendered_ordering_ids

    sign_in_as @teacher
    patch test_question_path(@exam, @ordering), params: {
      question: { texts: { "e1" => "First, corrected" } }
    }
    assert_equal I18n.t("exams.flash.question_updated"), flash[:notice]
    sign_out

    refute_empty before, "an empty render would make the comparison below meaningless"
    assert_equal before, rendered_ordering_ids,
      "the seed is the question and the attempt, so text must not move the order"
    assert_match "First, corrected", response.body
  end

  private

  def rendered_ordering_ids
    get student_run_url(token: @token)
    assert_response :success
    css_select("input[name='answers[#{@ordering.id}][order][]']").map { |el| el["value"] }
  end

  def assert_no_answer_key(body)
    @matching.reload
    refute_match(/is_correct/, body, "MCQ correctness flag reached the student")
    assert_select "input[type=radio][checked]", false, "a pre-checked option would be the key by another name"
    refute_match RUBRIC, body, "source rubric reached the student"
    refute_match MODEL_ANSWER, body, "open-question model answer reached the student"

    # The matching answer key is a left-id => right-id hash. Neither the mapping nor the
    # config key that holds it may appear.
    refute_match(/"pairs"|&quot;pairs&quot;/, body, "matching pairs key reached the student")
    @matching.pairs.each do |left_id, right_id|
      refute_match(/#{Regexp.escape(left_id)}\W{0,4}#{Regexp.escape(right_id)}/, body,
                   "matching pair #{left_id}=>#{right_id} reached the student")
    end
  end
end
