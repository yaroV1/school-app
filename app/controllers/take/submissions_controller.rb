module Take
  class SubmissionsController < BaseController
    def create
      attempt = @assignment.attempts.find(params.require(:attempt_id))
      AttemptLifecycle.submit!(attempt, answers: submitted_answers)
      redirect_to student_done_path(token: @assignment.access_token), notice: t("take.errors.submitted")
    rescue AttemptLifecycle::Expired
      redirect_to student_done_path(token: @assignment.access_token), alert: t("take.errors.time_up_kept")
    rescue AttemptLifecycle::NotAllowed => e
      redirect_to student_run_path(token: @assignment.access_token), alert: e.message
    rescue AttemptLifecycle::Conflict => e
      # Both Conflict paths — the answers write and the status write — roll back, so the attempt
      # is still in progress and the student can press submit again. Without this the exception
      # escapes the request.
      redirect_to student_run_path(token: @assignment.access_token), alert: e.message
    end

    def show
      @latest = @assignment.latest_finished_attempt
      return if @assignment.revoked? || !@exam.show_results_to_students? || @latest.nil?

      @grade = @latest.grade
      return unless @grade&.finalized_by_teacher?

      @results_visible = true
      @questions = @exam.questions.with_attached_photo
      @answers = @latest.answers.index_by(&:question_id)
    end

    private

    def submitted_answers
      return [] if params[:answers].blank?

      params[:answers].to_unsafe_h.map do |question_id, payload|
        { "question_id" => question_id, "payload" => payload }
      end
    end
  end
end
