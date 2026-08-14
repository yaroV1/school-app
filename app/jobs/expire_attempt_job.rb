class ExpireAttemptJob < ApplicationJob
  queue_as :default

  def perform(attempt_id)
    attempt = Attempt.find_by(id: attempt_id)
    return unless attempt

    AttemptLifecycle.expire_if_needed!(attempt)
  end
end
