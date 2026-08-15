# Teacher-facing live updates are a side effect of the student's request. The
# save has already committed by the time we broadcast, so a cable outage or a
# template error must not turn it into a 500 for a student mid-exam.
module LiveBroadcast
  def broadcast_safely
    yield
  rescue StandardError => error
    Rails.error.report(error, handled: true, source: "live_broadcast")
    Rails.logger.error("Live broadcast failed: #{error.class}: #{error.message}")
    nil
  end
end
