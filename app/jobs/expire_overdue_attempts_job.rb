class ExpireOverdueAttemptsJob < ApplicationJob
  queue_as :default

  def perform
    AttemptLifecycle.expire_overdue!(Attempt.overdue.includes(assignment: { exam: :questions }))
  end
end
