require "test_helper"

# The one-attempt report a teacher prints and hands to a parent. It leaves the building,
# so it renders the student's own work and never the answer key; that boundary is pinned
# in test/integration/answer_key_leak_test.rb. This file covers what it must show.
class AttemptReportTest < ActionDispatch::IntegrationTest
  RUBRIC       = "SENTINEL_REPORT_RUBRIC_DO_NOT_LEAK".freeze
  MODEL_ANSWER = "SENTINEL_REPORT_MODEL_ANSWER_DO_NOT_LEAK".freeze

  setup do
    @teacher = users(:one)
    @group = @teacher.class_groups.create!(name: "8-A")
    @exam = create_exam!(@teacher, title: "Quiz", status: :published, class_group: @group)

    @mcq = @exam.questions.create!(
      question_type: :mcq, prompt: "Capital?", points: 1, position: 0,
      config: { "options" => [
        { "id" => "a", "text" => "Paris", "is_correct" => false },
        { "id" => "b", "text" => "Kyiv", "is_correct" => true }
      ] }
    )
    @open = @exam.questions.create!(
      question_type: :open, prompt: "Explain", points: 2, position: 1,
      config: { "model_answer" => MODEL_ANSWER, "rubric" => RUBRIC }
    )

    # The two types where showing the KEY instead of the student's own work is the real
    # risk: the stored order is the answer, and the pairs map is the answer.
    @ordering = @exam.questions.create!(
      question_type: :ordering, prompt: "Order these", points: 3, position: 2,
      config: { "items" => [
        { "id" => "e1", "text" => "First" },
        { "id" => "e2", "text" => "Second" },
        { "id" => "e3", "text" => "Third" }
      ] }
    )
    @matching = @exam.questions.create!(
      question_type: :matching, prompt: "Match these", points: 2, position: 3,
      config: {
        "left" => [ { "id" => "l1", "text" => "Alpha" }, { "id" => "l2", "text" => "Beta" } ],
        "right" => [ { "id" => "r1", "text" => "One" }, { "id" => "r2", "text" => "Two" } ],
        "pairs" => { "l1" => "r1", "l2" => "r2" }
      }
    )

    @student = @teacher.students.create!(name: "Ada")
    @assignment = @exam.assignments.create!(student: @student)
    @attempt = @assignment.attempts.create!(
      attempt_no: 1, status: :submitted,
      started_at: 2.hours.ago, last_activity_at: 1.hour.ago, submitted_at: 1.hour.ago
    )
    @mcq_answer = @attempt.answers.create!(
      question: @mcq, payload: { "option_id" => "b" }, auto_score: 1
    )
    # Teacher-scored and not yet scored: effective_score is nil.
    @open_answer = @attempt.answers.create!(question: @open, payload: { "text" => "My essay" })
    # Both answered WRONG on purpose, so the student's own order and mapping differ from
    # the key. A report showing the key would be indistinguishable otherwise.
    @ordering_answer = @attempt.answers.create!(
      question: @ordering, payload: { "order" => %w[e3 e1 e2] }, auto_score: 0
    )
    @matching_answer = @attempt.answers.create!(
      question: @matching, payload: { "pairs" => { "l1" => "r2", "l2" => "r1" } }, auto_score: 0
    )
    @grade = @attempt.create_grade!(max_score: @exam.max_score, total_score: 2)

    sign_in_as @teacher
  end

  test "the report carries the student, class, subject, test, date and attempt number" do
    get report_attempt_path(@attempt)
    assert_response :success

    assert_select "article.print-sheet h2", text: @exam.title
    header = css_select("article.print-sheet header").first.text
    assert_includes header, @student.name
    assert_includes header, @group.name
    assert_includes header, @exam.subject.name
    assert_includes header, I18n.t("attempts.grade.attempt", n: 1)
    assert_includes header, I18n.l(@attempt.submitted_at, format: :short)
  end

  test "the report shows the total out of the maximum with a percentage" do
    get report_attempt_path(@attempt)

    header = css_select("article.print-sheet header").first.text
    assert_includes header, I18n.t("attempts.report.earned", score: 2, max: 8)
    assert_includes header, I18n.t("subjects.stats.percent", value: 25)
  end

  test "each question shows the student's own answer and what it earned" do
    get report_attempt_path(@attempt)

    mcq_block = css_select("##{dom_id(@mcq, :report)}").first.text
    assert_includes mcq_block, "Kyiv", "the student's chosen option"
    assert_includes mcq_block, I18n.t("attempts.report.earned", score: 1, max: 1)

    open_block = css_select("##{dom_id(@open, :report)}").first.text
    assert_includes open_block, "My essay"
  end

  test "ordering shows the student's own order, never the stored answer order" do
    get report_attempt_path(@attempt)

    rendered = css_select("##{dom_id(@ordering, :report)} ol li").map { |el| el.text.strip }
    assert_equal %w[Third First Second], rendered, "the student's order must be what prints"
    refute_equal @ordering.items.map { |item| item["text"] }, rendered,
                 "the report printed the answer order instead of the student's"
  end

  test "matching shows the student's own mapping, never the correct one" do
    get report_attempt_path(@attempt)

    rendered = css_select("##{dom_id(@matching, :report)} ul li").map { |el| el.text.squish }
    assert_equal [ "Alpha → Two", "Beta → One" ], rendered,
                 "the student's mapping must be what prints"
    refute_includes rendered, "Alpha → One", "the report printed the correct pair"
    refute_includes rendered, "Beta → Two", "the report printed the correct pair"
  end

  test "a teacher override wins over the machine score, and a zero reads as zero" do
    @mcq_answer.update!(teacher_score: 0)

    get report_attempt_path(@attempt)

    block = css_select("##{dom_id(@mcq, :report)}").first.text
    assert_includes block, I18n.t("attempts.report.earned", score: 0, max: 1),
                    "a scored zero must print as 0, not as a dash"
    refute_includes block, I18n.t("attempts.report.earned", score: 1, max: 1),
                    "the machine score was printed over the teacher's override"
  end

  test "a teacher-scored answer with no score prints a dash, not a zero" do
    get report_attempt_path(@attempt)

    open_block = css_select("##{dom_id(@open, :report)}").first.text
    assert_includes open_block,
                    I18n.t("attempts.report.earned", score: I18n.t("common.dash"), max: 2)
    refute_includes open_block, I18n.t("attempts.report.earned", score: 0, max: 2),
                    "an unscored answer must not read as a zero"
  end

  test "per-answer and overall teacher comments reach the report" do
    @open_answer.update!(teacher_score: 2, teacher_comment: "Good structure")
    @grade.update!(teacher_comment: "Well done overall")

    get report_attempt_path(@attempt)

    assert_select "##{dom_id(@open, :report)}", /Good structure/
    assert_select "article.print-sheet", /Well done overall/
    assert_select "article.print-sheet", /#{Regexp.escape(I18n.t('attempts.grade.overall_comment'))}/
  end

  test "an unfinalized grade is marked provisional and a finalized one is not" do
    get report_attempt_path(@attempt)
    assert_select "article.print-sheet header",
                  /#{Regexp.escape(I18n.t('attempts.report.provisional'))}/

    @grade.update!(finalized_by_teacher: true, finalized_at: Time.current)

    get report_attempt_path(@attempt)
    assert_select "article.print-sheet header",
                  text: /#{Regexp.escape(I18n.t('attempts.report.provisional'))}/, count: 0
  end

  test "an attempt with no grade row still renders, against the exam maximum" do
    @grade.destroy!

    get report_attempt_path(@attempt)
    assert_response :success

    header = css_select("article.print-sheet header").first.text
    assert_includes header, I18n.t("attempts.report.earned",
                                   score: I18n.t("common.dash"), max: @exam.max_score)
    assert_includes header, I18n.t("attempts.report.provisional")
  end

  test "an expired attempt still gets a report" do
    @attempt.update!(status: :expired)

    get report_attempt_path(@attempt)

    assert_response :success
    assert_select "article.print-sheet h2", text: @exam.title
  end

  test "a report is refused while the student is still writing" do
    @attempt.update!(status: :in_progress, submitted_at: nil)

    get report_attempt_path(@attempt)

    assert_redirected_to attempt_path(@attempt)
    assert_equal I18n.t("attempts.flash.report_in_progress"), flash[:alert]
  end

  # The report leaves the building in a schoolbag, so it is an answer-key boundary. The
  # canonical case lives in test/integration/answer_key_leak_test.rb; this is the same
  # guard at the point the boundary is created.
  test "the report carries no answer key and no access token" do
    get report_attempt_path(@attempt)
    assert_response :success
    body = response.body

    # What the report exists to carry, so an empty render cannot pass the refutes below.
    assert_match "My essay", body
    assert_match "Kyiv", body
    assert_match "Third", body

    refute_match(/is_correct/, body, "an mcq correctness flag reached the parent")
    refute_match(/"pairs"|&quot;pairs&quot;/, body, "the matching pairs key reached the parent")
    refute_match RUBRIC, body, "a rubric reached the parent"
    refute_match MODEL_ANSWER, body, "a model answer reached the parent"
    refute_match @assignment.access_token, body, "an assignment token reached the parent"

    # Deliberately NOT a whole-body refute of t("attempts.grade.correct_order"): that string
    # is byte-identical to t("question_types.ordering"), which the type chip prints, so it
    # would fail on every report carrying an ordering question. The two tests above scope
    # the same property to the answer blocks, where it can actually be violated.
    refute_match(/#{Regexp.escape(I18n.t('attempts.grade.pair_expected', value: 'One'))}/, body)
  end

  test "the screen chrome does not print and the report itself does" do
    get report_attempt_path(@attempt)

    assert_select ".no-print .breadcrumbs"
    assert_select ".no-print article.print-sheet", false,
                  "the report itself must survive printing"
  end

  test "another teacher cannot reach the report" do
    sign_in_as users(:two)

    get report_attempt_path(@attempt)

    assert_response :not_found
  end

  test "an unauthenticated request cannot reach the report" do
    sign_out

    get report_attempt_path(@attempt)

    assert_redirected_to new_session_path
  end
end
