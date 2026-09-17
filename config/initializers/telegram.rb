Rails.application.config.x.telegram = ActiveSupport::OrderedOptions.new
%i[bot_token bot_username webhook_secret app_url].each do |key|
  Rails.application.config.x.telegram[key] = ENV["TELEGRAM_#{key.to_s.upcase}"].presence ||
    Rails.application.credentials.dig(:telegram, key)
end
