module Take
  class PortalsController < BaseController
    def show
      @active_attempt = @assignment.in_progress_attempt
      AttemptLifecycle.expire_if_needed!(@active_attempt) if @active_attempt
      @active_attempt = @assignment.in_progress_attempt
      @can_start = @assignment.can_start?
      @attempts_used = @assignment.attempts_used
      @availability = @exam.availability_status
    end

    private

    def assignment_includes
      super + [ :attempts ]
    end
  end
end
