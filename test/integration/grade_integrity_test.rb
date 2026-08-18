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
  # A wording fix is the one teacher edit allowed while work is already recorded, so it
  # has to be provably inert: Scoring keys on entry ids, never on the text beside them.
  test "a wording fix moves no recorded work" do
    AttemptLifecycle.autosave!(@attempt, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])

    submitted = attempt_for("Bo")
    AttemptLifecycle.autosave!(submitted, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "b" } } ])
    AttemptLifecycle.submit!(submitted)

    finalized = attempt_for("Cy")
    AttemptLifecycle.autosave!(finalized, [ { "question_id" => @mcq.id, "payload" => { "option_id" => "a" } } ])
    AttemptLifecycle.submit!(finalized)
    finalized.answers.sole.update!(teacher_score: 0.5, teacher_comment: "half")
    finalized.grade.update!(total_score: 0.5, finalized_by_teacher: true, finalized_at: Time.current)

    attempts = [ @attempt, submitted, finalized ]
    before = scoring_snapshot(attempts)
    max_before = @exam.reload.max_score

    # Pin what the snapshot holds, so the comparison after the edit cannot pass on nothing.
    assert_equal %w[in_progress submitted submitted], before.map { |snap| snap[:status] }
    assert_equal [ 1, 0, 1 ], before.map { |snap| snap[:answers].first[1].to_i }
    assert_equal 0.5, before.last[:grade][0].to_f
    assert_equal 0.5, before.last[:answers].first[2].to_f
    assert_equal 1, before.last[:grade][1].to_i
    assert_equal 1, max_before.to_i
    assert before.last[:grade][2], "the third attempt must be finalized for this to mean anything"

    # Counted as a delta on purpose: assert_no_turbo_stream_broadcasts counts every
    # broadcast on the stream, and the autosaves above already pushed to grade_live.
    pushes_before = board_and_grade_pushes

    patch test_question_path(@exam, @mcq), params: {
      question: { prompt: "Capital of France?", texts: { "a" => "Parys", "b" => "Londres" } }
    }

    assert_equal pushes_before, board_and_grade_pushes,
      "a wording fix must push nothing to the live board or a grading page"

    assert_redirected_to test_path(@exam)
    assert_equal "Capital of France?", @mcq.reload.prompt
    assert_equal %w[Parys Londres], @mcq.options.map { |option| option["text"] },
      "the fix must actually land, or this test proves nothing"

    assert_equal before, scoring_snapshot(attempts)
    assert_equal max_before, @exam.reload.max_score
    assert_equal "a", @mcq.correct_option_id, "the answer key must not move"

    # Equality above is cheap for the in-progress attempt: nothing rescores it. submit! does,
    # against the config as it now stands, so this is where a bad rewrite would surface.
    AttemptLifecycle.submit!(@attempt)
    assert_equal 1, @attempt.answers.sole.reload.auto_score.to_i,
      "rescoring after the fix must still land on the option the student picked"
    assert_equal 1, @attempt.grade.reload.total_score.to_i
    assert_equal max_before, @attempt.grade.max_score
  end

  private

  def attempt_for(name)
    student = @teacher.students.create!(name: name)
    AttemptLifecycle.start!(@exam.assignments.create!(student: student))
  end

  def board_and_grade_pushes
    [ broadcasts(stream_name_from([ @exam, :live_board ])).size,
      broadcasts(stream_name_from([ @attempt, :grade_live ])).size ]
  end

  def scoring_snapshot(attempts)
    attempts.map do |attempt|
      attempt.reload
      grade = attempt.grade&.reload
      {
        status: attempt.status,
        answers: attempt.answers.reload.order(:question_id).map { |a| [ a.question_id, a.auto_score, a.teacher_score, a.payload ] },
        grade: grade && [ grade.total_score, grade.max_score, grade.finalized_by_teacher ]
      }
    end
  end
end
