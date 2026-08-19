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
      config: { "source" => "A short passage.", "rubric" => RUBRIC, "model_answer" => MODEL_ANSWER }
    )
    @open = @exam.questions.create!(
      question_type: :open, prompt: "Explain", points: 2, position: 4,
      config: { "model_answer" => MODEL_ANSWER, "rubric" => RUBRIC }
    )

    student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: student)
    @attempt = AttemptLifecycle.start!(@assignment)
    @token = @assignment.access_token
  end

  # Answers that are deliberately WRONG, so the student's own work is distinguishable from
  # the key. A report rendering the key would look identical if they matched.
  def answer_wrongly_and_submit!
    AttemptLifecycle.submit!(@attempt, answers: [
      { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } },
      { "question_id" => @ordering.id, "payload" => { "order" => %w[e4 e3 e2 e1] } },
      { "question_id" => @matching.id, "payload" => { "pairs" => { "l1" => "r1", "l2" => "r1" } } },
      { "question_id" => @source.id, "payload" => { "text" => "My source answer" } },
      { "question_id" => @open.id, "payload" => { "text" => "My open answer" } }
    ])
    @attempt.reload
    assert @attempt.submitted?, "the fixture attempt did not actually submit"
    @attempt
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

  # The printed sheet is the second answer-key boundary: the same question data, on paper,
  # handed to the same students, and unrevocable once photocopied. It renders through the
  # same student-facing readers, so it answers to the same assertions.
  test "the printed paper sheet carries no answer key" do
    sign_in_as @teacher

    get print_test_path(@exam)
    assert_response :success
    body = response.body

    # The content the sheet exists to carry, so a body that merely failed to render
    # cannot pass the refutes below.
    assert_match "Kyiv", body
    assert_match "A short passage.", body
    assert_match "Alpha", body
    assert_match "Explain", body

    assert_no_answer_key body
    refute_match @assignment.access_token, body,
                 "an assignment token reached a sheet that is handed to students"

    # Paper gives the key away by what is written beside a row, not by an id or a config
    # key, so every refute above is blind to it. Pin each block to exactly what the
    # student-facing reader returns: a marker, a letter or a star added to a row fails here.
    assert_equal @mcq.student_facing_options.map { |option| option["text"] },
                 rendered_texts(dom_id(@mcq, :print)),
                 "an mcq row carries something the student-facing reader did not return"
    assert_equal @matching.student_facing_left.map { |left| left["text"] },
                 css_select("##{dom_id(@matching, :print)} ul li").map { |el| el.text.squish },
                 "a matching left row carries something beyond its own text"
    assert_equal @ordering.unaligned_items(@exam.id).map { |item| item["text"] },
                 rendered_texts(dom_id(@ordering, :print)),
                 "the ordering block is not what the unaligned reader returned"
  end

  # The parent report is the third answer-key boundary: it leaves the building in a
  # schoolbag and cannot be recalled. It renders the student's own payload through the
  # student-facing readers, never attempts/_student_answer, which prints the key by design.
  test "the parent report carries no answer key" do
    answer_wrongly_and_submit!
    sign_in_as @teacher

    get report_attempt_path(@attempt)
    assert_response :success
    body = response.body

    # The student's own work, so an empty render cannot pass the refutes below.
    assert_match "My open answer", body
    assert_match "My source answer", body
    assert_match "Paris", body

    assert_no_answer_key body
    refute_match @token, body, "an assignment token reached a report sent home"

    # The student chose Paris, so the correct option must appear nowhere. Without this the
    # mcq block had no key guard at all: assert_no_answer_key checks is_correct, checked
    # radios, the sentinels and the pairs ids, and none of those is how an mcq key leaks here.
    refute_match "Kyiv", body, "the correct option reached the parent"

    # Refute the templates, not one interpolation of them: pinning value: "One" forbade a
    # single rendering and let every other one through.
    expected_marker = I18n.t("attempts.grade.pair_expected", value: "\u0000").split("\u0000").first
    refute_match expected_marker, body, "the expected-pair marker reached a parent"
    refute_match I18n.t("attempts.grade.pair_correct"), body, "a correctness marker reached a parent"

    # Structural and answer-independent: the teacher's grading partial roots every block at
    # dom_id(question, :student_answer), so this fails if it is ever rendered here at all.
    assert_select "[id^='student_answer_question_']", false,
                  "the teacher grading partial reached the report"
  end

  test "the report shows the student's own order and mapping, not the stored ones" do
    answer_wrongly_and_submit!
    sign_in_as @teacher

    get report_attempt_path(@attempt)
    assert_response :success

    order = css_select("##{dom_id(@ordering, :report)} ol li").map { |el| el.text.strip }
    assert_equal %w[Fourth Third Second First], order, "the student's own order must print"
    refute_equal @ordering.items.map { |item| item["text"] }, order

    mapping = css_select("##{dom_id(@matching, :report)} ul li").map { |el| el.text.squish }
    # Neither the key (Alpha->Two, Beta->One) nor the index-aligned default
    # (Alpha->One, Beta->Two): a view ignoring answer.pairs renders the latter, so an
    # identity payload would have proved nothing.
    assert_equal [ "Alpha → One", "Beta → One" ], mapping, "the student's own mapping must print"
    refute_includes mapping, "Alpha → Two", "the key reached the parent"
    refute_includes mapping, "Beta → Two", "the index-aligned default was printed, not the student"
  end

  private

  # Every answer row on the printed sheet is a box plus this span.
  def rendered_texts(block_id)
    texts = css_select("##{block_id} li span.pt-0\\.5").map { |el| el.text.strip }
    refute_empty texts, "an empty render would make the comparison meaningless"
    texts
  end

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
