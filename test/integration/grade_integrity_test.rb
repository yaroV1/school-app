require "test_helper"

class GradeIntegrityTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", status: :published, time_limit_sec: 600)
    @mcq = @exam.questions.create!(
      question_type: :mcq, prompt: "Capital?", points: 1, position: 0,
      config: { "options" => [
        { "id" => "a", "text" => "Paris", "is_correct" => true },
        { "id" => "b", "text" => "London", "is_correct" => false }
      ] }
    )
    @student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: @student)
    @attempt = AttemptLifecycle.start!(@assignment)
    sign_in_as @teacher
  end

  test "the teacher score field is not prefilled with the machine's score" do
    AttemptLifecycle.autosave!(@attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "b" } } ])

    get attempt_path(@attempt)
    assert_response :success
    assert_select "input[name='answers[][teacher_score]']" do |inputs|
      assert_nil inputs.first["value"], "an untouched teacher field must stay empty"
    end
    assert_match I18n.t("attempts.grade.auto_score_hint"), response.body
  end

  test "a student improving an answer mid-exam does not lose the point when the teacher saves" do
    # Student answers wrong; teacher opens the page while auto_score is 0.
    AttemptLifecycle.autosave!(@attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "b" } } ])
    get attempt_path(@attempt)
    assert_equal 0, @attempt.answers.sole.auto_score.to_i
    # Whatever the form actually rendered is what the teacher will post back.
    rendered_score = css_select("input[name='answers[][teacher_score]']").first["value"].to_s

    # Student fixes it while that page sits open.
    AttemptLifecycle.autosave!(@attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])
    assert_equal 1, @attempt.answers.sole.reload.auto_score.to_i

    # Teacher saves the form they loaded, without touching the score field.
    patch attempt_path(@attempt), params: {
      answers: [ { question_id: @mcq.id, teacher_score: rendered_score, teacher_comment: "" } ]
    }

    answer = @attempt.answers.sole.reload
    assert_nil answer.teacher_score, "a blank field must not record an override"
    assert_equal 1, answer.effective_score.to_i, "the student must keep the point they earned"
  end

  test "submitting does not move a grade the teacher already finalized" do
    AttemptLifecycle.autosave!(@attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])
    grade = @attempt.grade || @attempt.create_grade!(max_score: @exam.max_score)
    grade.update!(total_score: 0.5, finalized_by_teacher: true, finalized_at: Time.current)

    AttemptLifecycle.submit!(@attempt)

    grade.reload
    assert grade.finalized_by_teacher?
    assert_equal 0.5, grade.total_score.to_f, "a finalized total must survive the student's submit"
  end

  test "expiring does not move a grade the teacher already finalized" do
    AttemptLifecycle.autosave!(@attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])
    grade = @attempt.grade || @attempt.create_grade!(max_score: @exam.max_score)
    grade.update!(total_score: 0.5, finalized_by_teacher: true, finalized_at: Time.current)
    @attempt.update!(deadline_at: 1.minute.ago)

    AttemptLifecycle.expire_if_needed!(@attempt)

    assert @attempt.reload.expired?
    assert_equal 0.5, grade.reload.total_score.to_f, "a finalized total must survive expiry"
  end

  test "clearing the score field removes the override" do
    AttemptLifecycle.autosave!(@attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])

    patch attempt_path(@attempt), params: {
      answers: [ { question_id: @mcq.id, teacher_score: "0", teacher_comment: "" } ]
    }
    assert_equal 0, @attempt.answers.sole.reload.teacher_score.to_i, "the override should be recorded"

    # Teacher changes their mind and empties the field.
    patch attempt_path(@attempt), params: {
      answers: [ { question_id: @mcq.id, teacher_score: "", teacher_comment: "" } ]
    }

    answer = @attempt.answers.sole.reload
    assert_nil answer.teacher_score, "an emptied field must drop the override"
    assert_equal 1, answer.effective_score.to_i, "the auto score applies again"
  end

  test "a zero override is kept, not treated as blank" do
    AttemptLifecycle.autosave!(@attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])

    patch attempt_path(@attempt), params: {
      answers: [ { question_id: @mcq.id, teacher_score: "0", teacher_comment: "" } ]
    }

    answer = @attempt.answers.sole.reload
    assert_equal 0, answer.teacher_score.to_i
    assert_equal 0, answer.effective_score.to_i, "a deliberate zero must beat the auto score of 1"
  end

  test "an unfinalized grade still tracks the attempt" do
    AttemptLifecycle.autosave!(@attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])
    AttemptLifecycle.submit!(@attempt)

    assert_equal 1, @attempt.grade.reload.total_score.to_i
    assert_equal @exam.max_score, @attempt.grade.max_score
  end
end
