require "test_helper"

# A teacher fixing a typo while students are sitting the test. Wording may move;
# everything grading keys on may not, whatever the request carries.
class QuestionWordingTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @exam = create_exam!(@teacher, title: "Контрольна")
    @mcq = @exam.questions.create!(
      question_type: :mcq, prompt: "Столиця?", points: 2, position: 0,
      config: { "options" => [
        { "id" => "a", "text" => "Париж", "is_correct" => false },
        { "id" => "b", "text" => "Кийв", "is_correct" => true }
      ] }
    )
    @source = @exam.questions.create!(
      question_type: :source, prompt: "Перекажіть", points: 3, position: 1,
      config: { "source" => "Уривк тексту.", "rubric" => "секретна рубрика", "model_answer" => "секретна відповідь" }
    )
    @ordering = @exam.questions.create!(
      question_type: :ordering, prompt: "Впорядкуйте", points: 3, position: 2,
      config: { "items" => [
        { "id" => "i1", "text" => "Перша" },
        { "id" => "i2", "text" => "Друга" },
        { "id" => "i3", "text" => "Трета" }
      ] }
    )
    @matching = @exam.questions.create!(
      question_type: :matching, prompt: "Зіставте", points: 4, position: 3,
      config: {
        "left" => [ { "id" => "l1", "text" => "Альфа" }, { "id" => "l2", "text" => "Бета" } ],
        "right" => [ { "id" => "r1", "text" => "Один" }, { "id" => "r2", "text" => "Два" } ],
        "pairs" => { "l1" => "r2", "l2" => "r1" }
      }
    )
    @short = @exam.questions.create!(
      question_type: :short_text, prompt: "Хто написав?", points: 1, position: 4,
      config: { "rubric" => "секретна рубрика", "model_answer" => "секретна відповідь" }
    )
    @exam.publish!
  end

  test "a published question takes a corrected prompt and option text" do
    patch test_question_path(@exam, @mcq), params: {
      question: { prompt: "Столиця України?", texts: { "b" => "Київ" } }
    }

    assert_redirected_to test_path(@exam)
    assert_equal I18n.t("exams.flash.question_updated"), flash[:notice]

    @mcq.reload
    assert_equal "Столиця України?", @mcq.prompt
    assert_equal [ "Париж", "Київ" ], @mcq.options.map { |option| option["text"] }
    assert_equal "b", @mcq.correct_option_id
    assert_equal 2, @mcq.points
  end

  test "a published source question takes a corrected passage and keeps its key" do
    patch test_question_path(@exam, @source), params: {
      question: { source: "Уривок тексту." }
    }

    @source.reload
    assert_equal "Уривок тексту.", @source.source_text
    assert_equal "секретна рубрика", @source.rubric
    assert_equal "секретна відповідь", @source.model_answer
  end

  test "a published question ignores points, type, position, and extra option rows" do
    patch test_question_path(@exam, @mcq), params: {
      question: {
        prompt: "Столиця України?",
        points: 99,
        question_type: "short_text",
        position: 7,
        texts: { "b" => "Київ" },
        options: { "0" => { "text" => "Львів" } },
        correct_index: "0"
      }
    }

    assert_redirected_to test_path(@exam)

    @mcq.reload
    assert_equal "Столиця України?", @mcq.prompt
    assert_equal 2, @mcq.points
    assert @mcq.mcq?
    assert_equal 0, @mcq.position
    assert_equal [ "Париж", "Київ" ], @mcq.options.map { |option| option["text"] }
    assert_equal "b", @mcq.correct_option_id
  end

  test "a blank text keeps the entry's existing wording" do
    patch test_question_path(@exam, @mcq), params: {
      question: { prompt: "Столиця?", texts: { "a" => "", "b" => "Київ" } }
    }

    assert_equal [ "Париж", "Київ" ], @mcq.reload.options.map { |option| option["text"] }
  end

  test "an unknown id adds no entry" do
    patch test_question_path(@exam, @mcq), params: {
      question: { prompt: "Яка столиця?", texts: { "zzz" => "Привид" } }
    }

    assert_equal I18n.t("exams.flash.question_updated"), flash[:notice]

    @mcq.reload
    assert_equal "Яка столиця?", @mcq.prompt, "the save must have succeeded for this to prove anything"
    assert_equal %w[a b], @mcq.options.map { |option| option["id"] }
    assert_equal [ "Париж", "Кийв" ], @mcq.options.map { |option| option["text"] }
  end

  test "a nested or repeated text is refused, not stored" do
    patch test_question_path(@exam, @mcq), params: {
      question: { prompt: "Яка столиця?", texts: { "b" => { "nested" => "y" } } }
    }
    assert_equal "Кийв", @mcq.reload.options.last["text"]

    patch test_question_path(@exam, @mcq), params: {
      question: { prompt: "Яка столиця?", texts: { "b" => %w[x y] } }
    }
    assert_equal "Кийв", @mcq.reload.options.last["text"]
  end

  test "an ordering question keeps its answer key when an item is reworded" do
    patch test_question_path(@exam, @ordering), params: {
      question: { texts: { "i3" => "Третя" } }
    }

    @ordering.reload
    assert_equal [ "Перша", "Друга", "Третя" ], @ordering.items.map { |item| item["text"] }
    assert_equal %w[i1 i2 i3], @ordering.correct_order_ids
  end

  test "a matching question keeps its pairs when entries are reworded" do
    patch test_question_path(@exam, @matching), params: {
      question: { texts: { "l1" => "Альфа-1", "r1" => "Одиниця" }, pairs: { "0" => { "left" => "x", "right" => "y" } } }
    }

    @matching.reload
    assert_equal [ "Альфа-1", "Бета" ], @matching.left_items.map { |item| item["text"] }
    assert_equal [ "Одиниця", "Два" ], @matching.right_items.map { |item| item["text"] }
    assert_equal %w[l1 l2], @matching.left_items.map { |item| item["id"] }
    assert_equal %w[r1 r2], @matching.right_items.map { |item| item["id"] }
    assert_equal({ "l1" => "r2", "l2" => "r1" }, @matching.pairs)
  end

  test "a blank prompt is refused by validation, not by the lock" do
    patch test_question_path(@exam, @mcq), params: { question: { prompt: "  " } }

    assert_redirected_to test_path(@exam)
    assert_not_equal I18n.t("exams.flash.wording_locked"), flash[:alert]
    assert_not_equal I18n.t("exams.flash.question_updated"), flash[:notice]
    assert_equal "Столиця?", @mcq.reload.prompt
  end

  test "a blank source is refused rather than silently kept" do
    patch test_question_path(@exam, @source), params: {
      question: { prompt: "Перекажіть стисло", source: "  " }
    }

    assert_not_equal I18n.t("exams.flash.question_updated"), flash[:notice]

    @source.reload
    assert_equal "Уривк тексту.", @source.source_text
    assert_equal "Перекажіть", @source.prompt, "a refused save must not land the prompt either"
  end

  test "a closed test refuses a wording fix" do
    @exam.close!

    patch test_question_path(@exam, @mcq), params: { question: { prompt: "Пізно" } }

    assert_redirected_to test_path(@exam)
    assert_equal I18n.t("exams.flash.wording_locked"), flash[:alert]
    assert_equal "Столиця?", @mcq.reload.prompt
  end

  test "adding and removing questions stay draft-only" do
    assert_no_difference -> { @exam.questions.count } do
      post test_questions_path(@exam), params: {
        question: { question_type: "short_text", prompt: "Нове", points: 1 }
      }
    end
    assert_equal I18n.t("exams.flash.questions_locked"), flash[:alert]

    assert_no_difference -> { @exam.questions.count } do
      delete test_question_path(@exam, @mcq)
    end
    assert_equal I18n.t("exams.flash.questions_locked"), flash[:alert]
  end

  test "another teacher cannot reach the question" do
    sign_in_as users(:two)

    patch test_question_path(@exam, @mcq), params: { question: { prompt: "Чуже" } }

    assert_response :not_found
    assert_equal "Столиця?", @mcq.reload.prompt
  end

  test "the published test page renders a prefilled wording form for every question" do
    get test_path(@exam)
    assert_response :success

    assert_select "form[action=?]", test_question_path(@exam, @mcq) do
      assert_select "input[type=hidden][name=_method][value=patch]"
      assert_select "textarea[name=?]", "question[prompt]", text: /Столиця\?/
      assert_select "input[name=?][value=?]", "question[texts][a]", "Париж"
      assert_select "input[name=?][value=?]", "question[texts][b]", "Кийв"
    end

    assert_select "form[action=?]", test_question_path(@exam, @ordering) do
      assert_select "input[name=?][value=?]", "question[texts][i1]", "Перша"
      assert_select "input[name=?][value=?]", "question[texts][i2]", "Друга"
      assert_select "input[name=?][value=?]", "question[texts][i3]", "Трета"
    end

    assert_select "form[action=?]", test_question_path(@exam, @matching) do
      assert_select "input[name=?][value=?]", "question[texts][l1]", "Альфа"
      assert_select "input[name=?][value=?]", "question[texts][l2]", "Бета"
      assert_select "input[name=?][value=?]", "question[texts][r1]", "Один"
      assert_select "input[name=?][value=?]", "question[texts][r2]", "Два"
    end

    assert_select "form[action=?]", test_question_path(@exam, @source) do
      assert_select "textarea[name=?]", "question[source]", text: /Уривк тексту\./
    end
  end

  test "the wording form offers no structural control" do
    get test_path(@exam)

    assert_select "form[action=?]", test_question_path(@exam, @mcq) do
      assert_select "input[name=?]", "question[points]", false
      assert_select "input[name=?]", "question[correct_index]", false
      assert_select "input[type=radio]", false
      assert_select "select[name=?]", "question[question_type]", false
    end

    assert_select "form[action=?] input[type=text]", test_question_path(@exam, @mcq), count: 2
    assert_select "form[action=?] input[type=text]", test_question_path(@exam, @ordering), count: 3
    assert_select "form[action=?] input[type=text]", test_question_path(@exam, @matching), count: 4
    assert_select "form[action=?] input[type=text]", test_question_path(@exam, @source), count: 0
    assert_select "form[action=?] button", test_question_path(@exam, @mcq), false, "no add- or remove-row control"

    assert_select "form[action=?] textarea[name=?]", test_question_path(@exam, @short), "question[prompt]"
    assert_select "form[action=?] input[name^=?]", test_question_path(@exam, @short), "question[texts]", false

    assert_select "form[action=?] input[name=_method][value=delete]",
      test_question_path(@exam, @mcq), false, "remove stays draft-only"
    assert_select "form[action=?]", test_questions_path(@exam), false, "add stays draft-only"
    assert_no_match(/секретна рубрика/, response.body, "the form must carry wording, not the whole config")
    assert_no_match(/секретна відповідь/, response.body)
  end

  test "a closed test renders no wording form" do
    @exam.close!

    get test_path(@exam)

    assert_response :success
    assert_select "form[action=?]", test_question_path(@exam, @mcq), false
    assert_select "textarea[name=?]", "question[prompt]", false
  end

  test "a draft test renders the wording form beside the structural controls" do
    draft = create_exam!(@teacher, title: "Чернетка")
    question = draft.questions.create!(
      question_type: :mcq, prompt: "Чернеткове?", points: 1, position: 0,
      config: { "options" => [ { "id" => "d1", "text" => "Так", "is_correct" => true } ] }
    )

    get test_path(draft)

    assert_response :success
    assert_select "form[action=?] textarea[name=?]", test_question_path(draft, question), "question[prompt]"
    assert_select "form[action=?] input[name=_method][value=delete]", test_question_path(draft, question)
    assert_select "form[action=?]", test_questions_path(draft)
  end
  test "a wording form does not steal the add-question form's field ids" do
    draft = create_exam!(@teacher, title: "Чернетка")
    draft.questions.create!(
      question_type: :mcq, prompt: "Перше", points: 1, position: 0,
      config: { "options" => [ { "id" => "d1", "text" => "Так", "is_correct" => true } ] }
    )
    draft.questions.create!(
      question_type: :mcq, prompt: "Друге", points: 1, position: 1,
      config: { "options" => [ { "id" => "d2", "text" => "Ні", "is_correct" => true } ] }
    )

    get test_path(draft)

    ids = css_select("textarea[name='question[prompt]']").map { |node| node["id"] }
    assert_equal ids.uniq, ids, "a repeated id makes every label focus the first textarea"
    assert_equal 1, ids.count("question_prompt"), "only the add-question form owns the bare id"
  end
end
