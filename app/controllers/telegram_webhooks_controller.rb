class TelegramWebhooksController < ActionController::API
  def create
    secret = TelegramBot.settings.webhook_secret.to_s
    unless secret.present? && ActiveSupport::SecurityUtils.secure_compare(secret, request.headers["X-Telegram-Bot-Api-Secret-Token"].to_s)
      return head :unauthorized
    end

    reply = TelegramRegistration.call(params[:message])
    reply ? render(json: reply) : head(:ok)
  end
end
