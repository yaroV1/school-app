require "test_helper"

# The printed sheet is a second answer-key boundary: paper reaches students and cannot
# be revoked once photocopied. These tests cover what the sheet must show and what it
# must never show. The canonical key-absence case lives in answer_key_leak_test.rb;
# the refutes here are the same guard at the point the boundary is created.
#
# Sentinel strings rather than realistic copy, so a match cannot be a coincidence.
class ExamPrintTest < ActionDispatch::IntegrationTest
  RUBRIC       = "SENTINEL_PRINT_RUBRIC_DO_NOT_LEAK".freeze
  MODEL_ANSWER = "SENTINEL_PRINT_MODEL_ANSWER_DO_NOT_LEAK".freeze

  setup do
    @teacher = users(:one)
    @group = @teacher.class_groups.create!(name: "8-A")
    @exam = create_exam!(@teacher, title: "Quiz", status: :published, class_group: @group)

    # Positions deliberately do NOT follow insertion order, so "renders in position
    # order" cannot pass by accidentally agreeing with id order.
    @mcq = @exam.questions.create!(
      question_type: :mcq, prompt: "Capital?", points: 1, position: 0,
      # Four options with the correct one neither first nor last: two options with the
      # answer last cannot tell "reads is_correct" from "marks the last row".
      config: { "options" => [
        { "id" => "a", "text" => "Paris", "is_correct" => false },
        { "id" => "b", "text" => "Kyiv", "is_correct" => true },
        { "id" => "c", "text" => "Warsaw", "is_correct" => false },
        { "id" => "d", "text" => "Prague", "is_correct" => false }
      ] }
    )
    @short = @exam.questions.create!(
      question_type: :short_text, prompt: "In one word?", points: 1, position: 5, config: {}
    )
    @ordering = @exam.questions.create!(
      question_type: :ordering, prompt: "Order these", points: 2, position: 2,
      config: { "items" => (1..6).map { |n| { "id" => "e#{n}", "text" => "Event #{n}" } } }
    )
    @matching = @exam.questions.create!(
      question_type: :matching, prompt: "Match these", points: 3, position: 3,
      config: {
        # Three pairs, not the legal minimum of two: a two-entry bank deliberately keeps its
        # plain draw (Question#unaligned, and test/models/question_test.rb says why), so it
        # cannot exercise the FR-8 guarantee. The mapping is crossed so the answer sequence
        # is not plain right-item order, and one right item is multi-word so a test that
        # splits on whitespace cannot pass.
        "left" => [ { "id" => "l1", "text" => "Alpha" }, { "id" => "l2", "text" => "Beta" },
                    { "id" => "l3", "text" => "Gamma" } ],
        "right" => [ { "id" => "r1", "text" => "One" }, { "id" => "r2", "text" => "New York" },
                     { "id" => "r3", "text" => "Three" } ],
        "pairs" => { "l1" => "r2", "l2" => "r3", "l3" => "r1" }
      }
    )
    @source = @exam.questions.create!(
      question_type: :source, prompt: "Summarize it", points: 2, position: 4,
      config: { "source" => "A short passage.", "rubric" => RUBRIC }
    )
    @open = @exam.questions.create!(
      question_type: :open, prompt: "Explain", points: 2, position: 1,
      config: { "model_answer" => MODEL_ANSWER }
    )

    @assignment = @exam.assignments.create!(student: @teacher.students.create!(name: "Ada"))

    sign_in_as @teacher
  end

  test "the sheet renders every question in position order with its number, type, points and prompt" do
    get print_test_path(@exam)
    assert_response :success

    assert_select "article.print-sheet h2", text: @exam.title
    assert_select "article.print-sheet header", /#{Regexp.escape(@group.name)}/

    prompts = css_select("li.print-question p.whitespace-pre-wrap").map { |el| el.text.strip }
    assert_equal [ "Capital?", "Explain", "Order these", "Match these", "Summarize it", "In one word?" ],
                 prompts,
                 "questions did not render in position order"

    numbers = css_select("li.print-question > div > span.num").map { |el| el.text.strip }
    assert_equal %w[№1 №2 №3 №4 №5 №6], numbers

    assert_select "##{dom_id(@matching, :print)} .chip", text: I18n.t("question_types.matching")
    assert_select "##{dom_id(@matching, :print)}", /#{Regexp.escape(I18n.t('exams.points_short', count: 3))}/
  end

  test "the printed sheet carries no answer key" do
    get print_test_path(@exam)
    assert_response :success
    body = response.body

    # Visible content students need, so a body that merely failed to render cannot
    # pass the refutes below.
    assert_match "Kyiv", body
    assert_match "Alpha", body
    assert_match "A short passage.", body
    assert_match "Explain", body

    refute_match(/is_correct/, body, "MCQ correctness flag reached the sheet")
    refute_match RUBRIC, body, "source rubric reached the sheet"
    refute_match MODEL_ANSWER, body, "open-question model answer reached the sheet"
    refute_match(/"pairs"|&quot;pairs&quot;/, body, "matching pairs key reached the sheet")
    refute_match @assignment.access_token, body, "an assignment token reached a sheet handed to students"
    @matching.pairs.each do |left_id, right_id|
      refute_match(/#{Regexp.escape(left_id)}\W{0,4}#{Regexp.escape(right_id)}/, body,
                   "matching pair #{left_id}=>#{right_id} reached the sheet")
    end
  end

  test "every answer box on the sheet is blank and carries no marker" do
    get print_test_path(@exam)

    boxes = css_select("article.print-sheet .answer-box")
    refute_empty boxes, "an empty render would make the assertions below meaningless"
    boxes.each do |box|
      assert_equal "", box.text.strip, "a mark in a printed box would be the answer key"
      assert_equal [ "answer-box" ], box["class"].split,
                   "a marker class on a box would be the key by another name"
    end
  end

  test "the sheet carries blank name, class, date and score lines and the total points" do
    get print_test_path(@exam)

    %i[name_field class_field date_field score_field].each do |field|
      assert_select "article.print-sheet header dt", text: I18n.t("exams.print.#{field}")
    end
    assert_select "article.print-sheet header dd.fill-line", 4
    assert_select "article.print-sheet header", /#{Regexp.escape(I18n.t('exams.points', count: @exam.max_score))}/
  end

  test "mcq renders one box per student-facing option and no form input" do
    get print_test_path(@exam)

    assert_select "##{dom_id(@mcq, :print)} .answer-box", @mcq.student_facing_options.size
    assert_select "##{dom_id(@mcq, :print)}", /Paris/
    assert_select "##{dom_id(@mcq, :print)}", /Kyiv/
  end

  test "ordering renders the exam-seeded shuffle with an empty box per item" do
    shuffled = @ordering.unaligned_items(@exam.id)

    # FR-8 makes this an invariant, not a fixture canary: no seed may print the answer order.
    refute_equal @ordering.correct_order_ids, shuffled.map { |item| item["id"] },
                 "the printed ordering is the answer order"

    get print_test_path(@exam)

    rendered = css_select("##{dom_id(@ordering, :print)} li span.pt-0\\.5").map { |el| el.text.strip }
    assert_equal shuffled.map { |item| item["text"] }, rendered,
                 "ordering items did not render through unaligned_items(exam.id)"
    assert_select "##{dom_id(@ordering, :print)} .answer-box", shuffled.size
    assert_select "##{dom_id(@ordering, :print)}",
                  /#{Regexp.escape(I18n.t('exams.print.order_hint', count: shuffled.size))}/
  end

  test "the sheet renders the unaligned order, not the plain seeded shuffle" do
    exam = create_exam!(@teacher, title: "Aligned", status: :published, class_group: @group)

    # Build the one case that tells the two readers apart: a question whose plain draw IS
    # the answer order. Without it unaligned_items and shuffled_items agree and no
    # assertion here can catch the view calling the wrong one. Three items, so ~1 in 6.
    aligned = nil
    60.times do
      candidate = exam.questions.create!(
        question_type: :ordering, prompt: "Order", points: 1, position: 0,
        config: { "items" => (1..3).map { |n| { "id" => "e#{n}", "text" => "Event #{n}" } } }
      )
      break aligned = candidate if
        candidate.shuffled_items(exam.id).map { |item| item["id"] } == candidate.correct_order_ids

      candidate.destroy!
    end
    refute_nil aligned, "could not build a question whose plain draw is the answer order"

    get print_test_path(exam)
    assert_response :success

    rendered = css_select("##{dom_id(aligned, :print)} li span.pt-0\\.5").map { |el| el.text.strip }
    refute_equal aligned.items.map { |item| item["text"] }, rendered,
                 "the sheet printed the plain shuffle, which for this question is the answer order"
    assert_equal aligned.unaligned_items(exam.id).map { |item| item["text"] }, rendered
  end

  test "the exam seed is stable across reloads so every photocopy matches" do
    get print_test_path(@exam)
    first = css_select("##{dom_id(@ordering, :print)} li span.pt-0\\.5").map { |el| el.text.strip }
    get print_test_path(@exam)
    second = css_select("##{dom_id(@ordering, :print)} li span.pt-0\\.5").map { |el| el.text.strip }

    refute_empty first
    assert_equal first, second
  end

  test "matching renders a blank per left item and a lettered bank of shuffled right items" do
    get print_test_path(@exam)

    lefts = css_select("##{dom_id(@matching, :print)} ul li span.pt-0\\.5").map { |el| el.text.strip }
    assert_equal @matching.student_facing_left.map { |left| left["text"] }, lefts
    assert_select "##{dom_id(@matching, :print)} ul .answer-box", lefts.size

    bank_items = @matching.unaligned_right_items(@exam.id)

    # FR-8: reading the bank straight down must not answer the left column.
    answer_order = @matching.student_facing_left.map { |left| @matching.pairs[left["id"]] }
    refute_equal answer_order, bank_items.first(answer_order.size).map { |right| right["id"] },
                 "the printed bank letters the left column's answers in order"

    letters = I18n.t("exams.print.matching_letters").split
    expected = bank_items.each_with_index.map { |right, index| "#{letters[index]}. #{right['text']}" }
    bank = css_select("##{dom_id(@matching, :print)} ol li").map { |el| el.text.squish }

    assert_equal expected, bank, "the bank must be lettered and carry each right item in full"
    assert_select "##{dom_id(@matching, :print)}", /#{Regexp.escape(I18n.t('exams.print.matching_bank'))}/
  end

  test "short_text open and source render ruled writing space, and source shows its text" do
    get print_test_path(@exam)

    assert_select "##{dom_id(@short, :print)} .answer-line", 1
    assert_select "##{dom_id(@open, :print)} .answer-line", 6
    assert_select "##{dom_id(@source, :print)} .answer-line", 6
    assert_select "##{dom_id(@source, :print)} .source-text", text: "A short passage."
  end

  test "the sheet prints for a draft and a closed test as well as a published one" do
    %i[draft published closed].each do |status|
      @exam.update_column(:status, Exam.statuses[status])

      get print_test_path(@exam)
      assert_response :success, "a #{status} test must still be printable"
      assert_select "li.print-question", @exam.questions.count
    end
  end

  test "a test with no questions renders the header alone" do
    empty = create_exam!(@teacher, title: "Nothing yet", class_group: @group)

    get print_test_path(empty)
    assert_response :success
    assert_select "article.print-sheet h2", text: "Nothing yet"
    assert_select "li.print-question", false
  end

  test "screen chrome is marked no-print and the sheet is not" do
    get print_test_path(@exam)

    assert_select ".no-print .tab-bar"
    assert_select ".no-print .breadcrumbs"
    assert_select ".no-print", /#{Regexp.escape(I18n.t('exams.print.hint'))}/
    assert_select ".no-print article.print-sheet", false, "the sheet itself must survive printing"
  end

  test "the answer key marks the correct mcq option and no other" do
    get print_key_test_path(@exam)
    assert_response :success

    rows = css_select("##{dom_id(@mcq, :print_key)} li")
    assert_equal @mcq.options.size, rows.size, "every distractor must still print"

    marked = rows.select { |li| li.text.include?(I18n.t("exams.show.correct")) }
    assert_equal 1, marked.size, "exactly one option is the answer"
    correct = @mcq.options.find { |option| option["id"] == @mcq.correct_option_id }
    assert_includes marked.first.text, correct["text"]
  end

  test "the answer key lists the ordering in the stored answer order" do
    get print_key_test_path(@exam)

    rendered = css_select("##{dom_id(@ordering, :print_key)} ol li").map { |el| el.text.strip }
    assert_equal @ordering.items.map { |item| item["text"] }, rendered
  end

  test "the answer key lists every matching pair as left to right" do
    get print_key_test_path(@exam)

    expected = @matching.left_items.map do |left|
      right = @matching.right_items.find { |entry| entry["id"] == @matching.pairs[left["id"]] }
      "#{left['text']} → #{right['text']}"
    end
    assert_equal expected,
                 css_select("##{dom_id(@matching, :print_key)} ul li").map { |el| el.text.squish }
  end

  test "the answer key prints the rubric and the model answer" do
    get print_key_test_path(@exam)
    body = response.body

    assert_match RUBRIC, body
    assert_match MODEL_ANSWER, body
    assert_select "##{dom_id(@source, :print_key)}",
                  /#{Regexp.escape(I18n.t('exams.show.rubric'))}/
    assert_select "##{dom_id(@open, :print_key)}",
                  /#{Regexp.escape(I18n.t('exams.show.model_answer'))}/

    # A question with neither must show neither label, or every mcq and ordering block
    # would print an empty "Критерії" heading.
    bare = css_select("##{dom_id(@short, :print_key)}").first.text
    refute_includes bare, I18n.t("exams.show.rubric")
    refute_includes bare, I18n.t("exams.show.model_answer")
  end

  test "the answer key warns on screen and still names itself on paper" do
    get print_key_test_path(@exam)

    assert_select ".no-print", /#{Regexp.escape(I18n.t('exams.print_key.warning'))}/
    # The warning is chrome, but a key left on a desk still has to say what it is.
    assert_select "article.print-sheet header",
                  /#{Regexp.escape(I18n.t('exams.print_key.heading'))}/
    assert_select ".no-print article.print-sheet", false,
                  "the key sheet itself must survive printing"
  end

  test "an unauthenticated request reaches neither sheet" do
    sign_out

    get print_test_path(@exam)
    assert_redirected_to new_session_path

    get print_key_test_path(@exam)
    assert_redirected_to new_session_path
    refute_match RUBRIC, response.body
    refute_match MODEL_ANSWER, response.body
  end

  test "another teacher cannot print the answer key" do
    sign_in_as users(:two)

    get print_key_test_path(@exam)

    assert_response :not_found
  end

  test "another teacher cannot print the sheet" do
    sign_in_as users(:two)

    get print_test_path(@exam)

    assert_response :not_found
  end
end
