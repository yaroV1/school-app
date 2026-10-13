module Take
  class FocusEventsController < BaseController
    before_action :require_device

    def create
      attempt = @assignment.attempts.find(params.require(:attempt_id))
      AttemptLifecycle.record_focus_loss!(attempt)
      head :no_content
    end

    private

    def reject_other_device
      head :forbidden
    end
  end
end
