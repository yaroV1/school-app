class TelegramDelivery
  def self.enqueue(assignment, wait: 0.seconds)
    request_id = SecureRandom.uuid
    assignment.with_lock do
      return false unless assignment.exam.published? && !assignment.revoked? && !assignment.student.archived?
      return false unless assignment.student.telegram_chat_id.present?
      return false if assignment.telegram_delivery_pending?

      assignment.update!(telegram_status: "queued", telegram_request_id: request_id,
        telegram_chat_id: assignment.student.telegram_chat_id,
        telegram_token_digest: Digest::SHA256.hexdigest(assignment.access_token),
        telegram_requested_at: Time.current, telegram_sent_at: nil, telegram_error: nil)
    end
    job = TelegramDeliveryJob.set(wait: wait).perform_later(assignment.id, request_id)
    unless job
      fail_request(assignment.id, request_id, "queue_failed")
      return false
    end
    true
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    fail_request(assignment.id, request_id, "queue_failed")
    false
  end

  def self.deliver(assignment_id, request_id)
    scope = Assignment.where(id: assignment_id, telegram_request_id: request_id)
    return unless scope.where(telegram_status: "queued").update_all(telegram_status: "sending") == 1

    assignment = scope.includes(:student, :exam).first
    return unless assignment

    unless assignment.exam.published? && !assignment.revoked? && !assignment.student.archived? &&
        assignment.student.telegram_chat_id == assignment.telegram_chat_id &&
        Digest::SHA256.hexdigest(assignment.access_token) == assignment.telegram_token_digest
      return fail_request(assignment_id, request_id, "changed")
    end

    TelegramBot.send_message(chat_id: assignment.telegram_chat_id,
      text: I18n.t("telegram.bot.test", title: assignment.exam.title.truncate(200),
        url: assignment.access_url(base_url: TelegramBot.settings.app_url.to_s.delete_suffix("/"))))
    scope.update_all(telegram_status: "sent", telegram_sent_at: Time.current, telegram_error: nil)
  rescue TelegramBot::Error => error
    fail_request(assignment_id, request_id, error.code)
  end

  def self.fail_request(assignment_id, request_id, code)
    Assignment.where(id: assignment_id, telegram_request_id: request_id)
      .update_all(telegram_status: "failed", telegram_error: code)
  end
  private_class_method :fail_request
end
