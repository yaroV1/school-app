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
        return redirect_to student_portal_path(token: @assignment.access_token), alert: t("take.errors.start_first")
      end

      AttemptLifecycle.expire_if_needed!(@attempt)
      if @attempt.expired?
        return redirect_to student_done_path(token: @assignment.access_token), alert: t("take.errors.time_up")
      end

      @questions = @exam.questions.with_attached_photo
      @answers = @attempt.answers.index_by(&:question_id)
    end

    private

    def assignment_includes
      super + [ :attempts ]
    end
  end
end
