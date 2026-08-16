require "test_helper"

# A save conflict is the one failure a student cannot retry their way out of if it reaches
# them as an error page. These tests drive the real unauthenticated /t/:token endpoints and
# assert the conflict ends in take.errors.save_conflict instead.
#
# Red vs green here is "does the request return at all": `test.rb` sets
# `show_exceptions = :rescuable`, and AttemptLifecycle::Conflict has no rescue_responses
# mapping, so without the controller rescue the exception escapes the request entirely. In
# production that same escape is a 500 page, and autosave_controller.js falls back to the
# generic take.save_failed because the body is not JSON.
#
# In production the collision originates in `locked.update!(last_activity_at:)` — `attempts`
# is the only table carrying lock_version. Nothing can inject there from outside, so the
# scorer inside the same transaction stands in for it: same begin/rescue, same retry count.
# `replacing` is in test_helper.rb.
class SaveConflictTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", status: :published, time_limit_sec: 600)
    @question = @exam.questions.create!(
      question_type: :mcq, prompt: "Capital?", points: 1, position: 0,
      config: { "options" => [
        { "id" => "a", "text" => "Paris", "is_correct" => false },
        { "id" => "b", "text" => "Kyiv", "is_correct" => true }
      ] }
    )
    @student = @teacher.students.create!(name: "Lin")
    @assignment = @exam.assignments.create!(student: @student)
    @attempt = AttemptLifecycle.start!(@assignment)
    @token = @assignment.access_token
  end

  def collide
    ->(*) { raise ActiveRecord::StaleObjectError.new(Attempt.new, "update") }
  end

  def autosave!
    put student_answers_url(token: @token),
        params: { attempt_id: @attempt.id, answers: [ { question_id: @question.id, payload: { option_id: "b" } } ] },
        as: :json
  end

  test "an autosave that conflicts answers with the save_conflict message, not an escaped exception" do
    replacing(Scoring, :score_auto!, collide) { autosave! }

    assert_response :unprocessable_entity
    assert_equal I18n.t("take.errors.save_conflict"), response.parsed_body["error"]
    assert @attempt.reload.in_progress?
  end

  test "the student can keep working after a conflicted autosave" do
    replacing(Scoring, :score_auto!, collide) { autosave! }
    assert_equal 0, @attempt.answers.reload.count, "the conflicted write must roll back"

    # The property the rescue actually buys: the runner's next 5s tick succeeds. Without it
    # the exception escapes the request and the student's session is over.
    autosave!

    assert_response :success
    assert_equal 1, @attempt.answers.reload.count
    assert_equal "b", @attempt.answers.first.option_id
  end
end
