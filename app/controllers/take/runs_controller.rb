module Take
  class RunsController < BaseController
    def create
      @attempt = AttemptLifecycle.start!(@assignment)
      redirect_to student_run_path(token: @assignment.access_token)
    rescue AttemptLifecycle::NotAllowed => e
      redirect_to student_portal_path(token: @assignment.access_token), alert: e.message
    end

    def show
      @attempt = @assignment.in_progress_attempt
      unless @attempt
        return redirect_to student_portal_path(token: @assignment.access_token), alert: "Start the test first."
      end

      AttemptLifecycle.expire_if_needed!(@attempt)
      if @attempt.expired?
        return redirect_to student_done_path(token: @assignment.access_token), alert: "Time is up."
      end

      @questions = @exam.questions
      @answers = @attempt.answers.index_by(&:question_id)
    end
  end
end
