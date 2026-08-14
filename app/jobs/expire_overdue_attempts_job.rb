class ExpireOverdueAttemptsJob < ApplicationJob
  queue_as :default

  def perform
    Attempt.overdue.find_each do |attempt|
      AttemptLifecycle.expire_if_needed!(attempt)
    end
  end
end
