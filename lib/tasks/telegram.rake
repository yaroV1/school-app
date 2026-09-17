namespace :telegram do
  desc "Register the configured Telegram bot webhook (changes Telegram settings)"
  task set_webhook: :environment do
    TelegramBot.set_webhook
    puts I18n.t("telegram.webhook_registered")
  rescue TelegramBot::Error => error
    abort error.message
  end
end
