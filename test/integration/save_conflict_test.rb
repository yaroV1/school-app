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
# The collision is injected, and has to be. `attempts` is the only table carrying lock_version,
# and both write paths below read it inside an `Attempt.transaction` — which is IMMEDIATE, so it
# holds the SQLite write lock from BEGIN to COMMIT and nothing else can commit in the window
# between the read and the write. So these pin the rescue contract, not a race this adapter can
# reach; the scorer stands in for the write, with the same begin/rescue and retry count. The one
# path that genuinely loses the race is the one that reads *outside* a transaction — `expire!`,
# covered in test/services/attempt_lifecycle_test.rb against a real stale row rather than a stub.
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

  # partial_total sits inside submit!'s transaction, after the status write, so save_answers!
  # (when answers are passed) commits first and only the submit transaction rolls back.
  def conflicted_submit!(answers: nil)
    params = { attempt_id: @attempt.id }
    params[:answers] = answers if answers
    replacing(Scoring, :partial_total, collide) do
      post student_submit_url(token: @token), params: params
    end
  end

  def autosave!
    put student_answers_url(token: @token),
        params: { attempt_id: @attempt.id, answers: [ { question_id: @question.id, payload: { option_id: "b" } } ] },
        as: :json
  end

  test "an autosave that conflicts answers with the save_conflict message, not an escaped exception" do
    grade_streams = capture_turbo_stream_broadcasts [ @attempt, :grade_live ] do
      replacing(Scoring, :score_auto!, collide) { autosave! }
    end

    assert_empty grade_streams, "a conflicted autosave must not push a partial update"
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

  test "a submit that conflicts returns to the run page with the save_conflict alert" do
    attempt_id = @attempt.id
    status_at_collision = nil
    # partial_total, not score_auto!: refresh_grade! reaches it *after* the status write. Recording
    # the status here rather than asserting it in a comment means a reorder — or refresh_grade!
    # short-circuiting on a finalized grade — cannot silently make the rollback assertions vacuous.
    # `self` is rebound to Scoring inside, so the id is captured as a local.
    collide_after_status = lambda do |*|
      status_at_collision = Attempt.find(attempt_id).status
      raise ActiveRecord::StaleObjectError.new(Attempt.new, "update")
    end

    replacing(Scoring, :partial_total, collide_after_status) do
      post student_submit_url(token: @token),
           params: { attempt_id: @attempt.id, answers: { @question.id => { option_id: "b" } } }
    end

    assert_equal "submitted", status_at_collision, "the collision must fire after the status write"
    assert_redirected_to student_run_url(token: @token)
    assert_equal I18n.t("take.errors.save_conflict"), flash[:alert]

    # The Location header alone does not prove the student sees a page rather than an error.
    follow_redirect!
    assert_response :success

    assert @attempt.reload.in_progress?, "the rolled-back submit must leave the attempt submittable"
    assert_nil @attempt.submitted_at
    # save_answers! commits before submit!'s transaction opens, so the answers survive the rollback.
    assert_equal "b", @attempt.answers.reload.first.option_id
  end

  test "the student can submit again after a conflicted submit" do
    replacing(Scoring, :partial_total, collide) do
      post student_submit_url(token: @token), params: { attempt_id: @attempt.id }
    end

    post student_submit_url(token: @token), params: { attempt_id: @attempt.id }

    assert_redirected_to student_done_url(token: @token)
    assert @attempt.reload.submitted?
    assert @attempt.submitted_at.present?

    # refresh_grade! is the step that blew up the first time; prove the retry actually redid it,
    # rather than flipping the status and skipping the grading.
    grade = @attempt.grade
    assert_not_nil grade, "the successful submit must write the grade the conflict rolled back"
    assert_equal 0.0, grade.total_score.to_f
    assert_equal @exam.max_score, grade.max_score
  end

  # An assert_empty over a mis-scoped capture passes trivially, so each block is paired with a
  # successful submit through the same keys. Without that control a renamed streamable would make
  # this test silently vacuous — which is how three earlier assertions in this PRD failed.
  test "a conflicted submit broadcasts nothing to the teacher" do
    board = nil
    grade = capture_turbo_stream_broadcasts [ @attempt, :grade_live ] do
      board = capture_turbo_stream_broadcasts [ @exam, :live_board ] do
        conflicted_submit!
      end
    end

    assert_empty board, "the teacher board must not move for a submit that failed"
    assert_empty grade, "the grading page must not move for a submit that failed"

    board_ok = nil
    grade_ok = capture_turbo_stream_broadcasts [ @attempt, :grade_live ] do
      board_ok = capture_turbo_stream_broadcasts [ @exam, :live_board ] do
        post student_submit_url(token: @token), params: { attempt_id: @attempt.id }
      end
    end

    refute_empty board_ok, "capture keys are stale: a real submit moves the board"
    refute_empty grade_ok, "capture keys are stale: a real submit moves the grading page"
  end

  # Was the pin on a known gap; now pins its closure. save_answers! commits the answers in its own
  # transaction and skips broadcasting, on the promise that submit! will push one update for the
  # lot. Conflict used to break that promise, leaving the answers durable but invisible to a teacher
  # watching live — with no later broadcast to correct it on an untimed exam, which never expires.
  test "a conflicted submit still pushes the answers it committed" do
    board = nil
    grade = capture_turbo_stream_broadcasts [ @attempt, :grade_live ] do
      board = capture_turbo_stream_broadcasts [ @exam, :live_board ] do
        conflicted_submit!(answers: { @question.id => { option_id: "b" } })
      end
    end

    assert_equal 1, @attempt.answers.reload.count, "save_answers! commits before submit!'s transaction"
    assert_empty board, "no submission happened, so the board is correctly silent"
    assert_equal 1, grade.size, "the committed answer must reach the teacher"
    assert_equal ActionView::RecordIdentifier.dom_id(@question, :student_answer), grade.sole["target"],
                 "a mismatched target updates nothing and fails no other assertion"
    assert_includes grade.sole.to_s, "Kyiv", "the pushed block must carry the answer that was saved"
  end

  # The header belongs to the submission, which rolled back: pushing it would show the teacher a
  # submitted attempt the student can still edit.
  test "a conflicted submit pushes no header, only answers" do
    grade = capture_turbo_stream_broadcasts [ @attempt, :grade_live ] do
      conflicted_submit!(answers: { @question.id => { option_id: "b" } })
    end

    refute_includes grade.map { |stream| stream["target"] }, "attempt_live_header"
  end

  # The answers write and the status write both raise Conflict. Only the second one has committed
  # answers behind it; the first rolls its own back and must stay silent.
  test "a submit whose answer write conflicts broadcasts nothing" do
    grade = capture_turbo_stream_broadcasts [ @attempt, :grade_live ] do
      replacing(Scoring, :score_auto!, collide) do
        post student_submit_url(token: @token),
             params: { attempt_id: @attempt.id, answers: { @question.id => { option_id: "b" } } }
      end
    end

    assert_equal 0, @attempt.answers.reload.count, "the conflicted answer write must roll back"
    assert_empty grade, "nothing was committed, so there is nothing to push"
  end

  # expire_if_needed! runs at the top of save_answers!, *outside* its rescue, and expire! reads under
  # the lock with no transaction around it. A writer landing in that window used to raise
  # StaleObjectError straight through the action — which Rails maps to 409, so the body is not JSON
  # and autosave_controller.js shows the generic failure instead of sending the student to /done.
  test "an autosave whose expiry loses the lock_version race still answers the student" do
    @attempt.update!(deadline_at: 1.minute.ago)
    stale = Attempt.find(@attempt.id)
    Attempt.find(@attempt.id).update!(last_activity_at: Time.current)

    stale_relation = Object.new
    stale_relation.define_singleton_method(:find) { |_id| stale }
    # Only the first read is stale: the losing writer is expire!, and the transaction that follows
    # reads the row again for real.
    original_lock = Attempt.method(:lock)
    reads = 0
    first_read_is_stale = lambda do |*args|
      reads += 1
      reads == 1 ? stale_relation : original_lock.call(*args)
    end

    replacing(Attempt, :lock, first_read_is_stale) { autosave! }

    assert_response :unprocessable_entity
    assert_equal I18n.t("take.errors.time_up"), response.parsed_body["error"]
    assert_equal "expired", response.parsed_body["status"], "the runner needs this to send the student to /done"
  end

  test "the autosave conflict payload carries nothing but the message" do
    replacing(Scoring, :score_auto!, collide) { autosave! }

    assert_response :unprocessable_entity
    assert_equal %w[error], response.parsed_body.keys, "the conflict payload must carry only the message"
    refute_includes response.body, @token, "the autosave conflict payload leaked the access token"
  end

  # The token is in the Location header by design: every /t/:token URL carries it, including the
  # run page's own form action and autosave URL. The *body* is not, and at actionpack 8.1
  # redirect_to sets an empty body, so this is checkable rather than unwinnable. The two
  # assertions above the refute exist so the refute cannot pass on a submit that never conflicted.
  test "the submit conflict response body carries no access token" do
    conflicted_submit!

    assert_redirected_to student_run_url(token: @token)
    assert_equal I18n.t("take.errors.save_conflict"), flash[:alert]
    refute_includes response.body, @token, "the submit conflict body leaked the access token"
  end
end
