module Take
  class SubmissionsController < BaseController
    def create
      attempt = @assignment.attempts.find(params.require(:attempt_id))
      if params[:answers].present?
        answers = params[:answers].to_unsafe_h.map do |question_id, payload|
          { "question_id" => question_id, "payload" => payload }
        end
        AttemptLifecycle.autosave!(attempt, answers)
      end
      AttemptLifecycle.submit!(attempt)
      redirect_to student_done_path(token: @assignment.access_token), notice: t("take.errors.submitted")
    rescue AttemptLifecycle::Expired
      redirect_to student_done_path(token: @assignment.access_token), alert: t("take.errors.time_up_kept")
    rescue AttemptLifecycle::NotAllowed => e
      redirect_to student_run_path(token: @assignment.access_token), alert: e.message
    end

    def show
      @latest = @assignment.attempts.where(status: %i[submitted expired]).order(attempt_no: :desc).first
    end
  end
end
