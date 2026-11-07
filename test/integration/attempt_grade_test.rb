require "test_helper"

class AttemptGradeTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher

    @exam = create_exam!(@teacher, title: "Quiz", status: :published)
    @question = @exam.questions.create!(
      question_type: :short_text,
      prompt: "Sky?",
      points: 1,
      position: 0,
      config: {}
    )
    @student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: @student)
    @attempt = AttemptLifecycle.start!(@assignment)
  end

  test "grade page subscribes to live student answers" do
    get attempt_path(@attempt)
    assert_response :success
    assert_select "turbo-cable-stream-source"
    assert_select "#attempt_live_header"
    assert_select "#student_answer_question_#{@question.id}"
    assert_match I18n.t("attempts.grade.live_hint"), response.body
    assert_select "input[name='answers[][teacher_score]']"
  end

  test "the finalize control is labelled, not captioned with its own flag value" do
    get attempt_path(@attempt)
    assert_response :success
    # submit_tag lets an options hash overwrite its label argument, so passing
    # value: "1" for the finalize flag rendered a button captioned "1".
    assert_select "button[type=submit][name=finalize][value=?]", "1",
      text: I18n.t("attempts.grade.save_finalize")
  end

  test "submitted attempt hides the live writing hint and opens no subscription" do
    AttemptLifecycle.submit!(@attempt)
    get attempt_path(@attempt)
    assert_response :success
    refute_match I18n.t("attempts.grade.live_hint"), response.body
    # Nothing broadcasts to a finished attempt, so a teacher grading a stack of
    # them should not leave a websocket open per page.
    assert_select "turbo-cable-stream-source", false
  end

  # Credits hang off Grade#finalize!, so saving a score without finalizing must pay nothing:
  # a draft total is still moving.
  test "credits are awarded when the teacher finalizes, not when a score is saved" do
    AttemptLifecycle.submit!(@attempt)

    patch attempt_path(@attempt), params: {
      answers: [ { question_id: @question.id, teacher_score: "1" } ]
    }
    assert_equal 0, @student.credit_balance

    patch attempt_path(@attempt), params: {
      answers: [ { question_id: @question.id, teacher_score: "1" } ], finalize: "1"
    }
    assert_equal I18n.t("attempts.flash.finalized"), flash[:notice]
    assert_equal Credits::PER_TEST, @student.credit_balance
  end

  test "a refused finalize marks the missing teacher score and leaves an auto score alone" do
    scored = @exam.questions.create!(
      question_type: :short_text, prompt: "Already scored", points: 1, position: 1, config: {}
    )
    mcq = @exam.questions.create!(
      question_type: :mcq,
      prompt: "2+2?",
      points: 1,
      position: 2,
      config: {
        "options" => [
          { "id" => "a", "text" => "3", "is_correct" => false },
          { "id" => "b", "text" => "4", "is_correct" => true }
        ]
      }
    )
    AttemptLifecycle.submit!(@attempt)
    @attempt.answers.create!(question: mcq, payload: { "option_id" => "b" }, auto_score: 1)

    patch attempt_path(@attempt), params: {
      answers: [
        { question_id: scored.id, teacher_score: "1" },
        { question_id: @question.id, teacher_score: "" },
        { question_id: mcq.id, teacher_score: "" }
      ],
      finalize: "1"
    }

    assert_redirected_to attempt_path(@attempt, anchor: "teacher_score_question_#{@question.id}")
    assert_equal I18n.t("attempts.flash.need_scores"), flash[:alert]
    assert_equal [ @question.id ], flash[:unscored_question_ids]

    follow_redirect!
    assert_select "input##{dom_id(@question, :teacher_score)}.field-invalid[aria-invalid=true]"
    assert_select "p##{dom_id(@question, :score_required)}.field-error", text: I18n.t("attempts.grade.score_required")
    assert_select "input##{dom_id(scored, :teacher_score)}.field-invalid", count: 0
    assert_select "input##{dom_id(mcq, :teacher_score)}.field-invalid", count: 0
    assert_select "input.field-invalid", count: 1
  end

  test "saving without finalizing does not mark empty scores" do
    AttemptLifecycle.submit!(@attempt)

    patch attempt_path(@attempt), params: {
      answers: [ { question_id: @question.id, teacher_score: "" } ]
    }

    assert_redirected_to attempt_path(@attempt)
    follow_redirect!
    assert_select "input.field-invalid", count: 0
    assert_select "p.field-error", count: 0
  end

  private

  def dom_id(record, prefix)
    ApplicationController.helpers.dom_id(record, prefix)
  end
end
