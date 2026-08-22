module Take
  class FocusEventsController < BaseController
    def create
      attempt = @assignment.attempts.find(params.require(:attempt_id))
      AttemptLifecycle.record_focus_loss!(attempt)
      head :no_content
    end
  end
end
