class TelegramRegistration
  def self.call(message)
    return unless message.is_a?(ActionController::Parameters) || message.is_a?(Hash)
    return unless message.dig("chat", "type") == "private"

    chat_id = message.dig("chat", "id")
    return unless chat_id.is_a?(Integer) && chat_id.positive? && chat_id == message.dig("from", "id")
    return if message.dig("from", "is_bot")

    token = message["text"].to_s.match(/\A\/start(?:@\w+)?\s+([A-Za-z0-9_-]{1,64})\z/)&.captures&.first
    group = ClassGroup.find_by(telegram_join_token: token) if token
    username = message.dig("from", "username").to_s.downcase.presence
    result = "not_matched"

    if group && username
      Student.transaction do
        student = group.students.active.where(teacher_id: group.teacher_id).find_by(telegram_username: username)
        if student&.telegram_chat_id == chat_id
          result = "connected"
        elsif student && student.telegram_chat_id.nil? &&
            (student.telegram_pending_chat_id.nil? || student.telegram_pending_chat_id == chat_id)
          student.update!(telegram_pending_chat_id: chat_id,
            telegram_pending_name: [ message.dig("from", "first_name"), message.dig("from", "last_name") ].compact.join(" ").truncate(150))
          result = "pending"
        end
      end
    end

    { method: "sendMessage", chat_id: chat_id, text: I18n.t("telegram.bot.#{result}") }
  end
end
