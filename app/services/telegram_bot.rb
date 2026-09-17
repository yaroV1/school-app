require "net/http"

class TelegramBot
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(I18n.t("telegram.errors.#{code}"))
    end
  end

  def self.settings
    Rails.application.config.x.telegram
  end

  def self.configured?
    %i[bot_token bot_username webhook_secret app_url].all? { |key| settings[key].present? } &&
      settings.app_url.match?(%r{\Ahttps://[^/]+})
  end

  def self.join_url(class_group)
    "https://t.me/#{settings.bot_username}?start=#{class_group.telegram_join_token}"
  end

  def self.send_message(chat_id:, text:)
    request("sendMessage", chat_id: chat_id, text: text, link_preview_options: { is_disabled: true })
  end

  def self.set_webhook
    request("setWebhook", url: "#{settings.app_url.to_s.delete_suffix('/')}/telegram/webhook",
      secret_token: settings.webhook_secret, allowed_updates: [ "message" ], max_connections: 1)
  end

  def self.request(method, payload)
    raise Error, "not_configured" unless configured?

    uri = URI("https://api.telegram.org/bot#{settings.bot_token}/#{method}")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = payload.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 10) do |http|
      http.request(request)
    end
    body = JSON.parse(response.body)
    return if response.is_a?(Net::HTTPSuccess) && body["ok"] == true

    code = case body["error_code"]
    when 403 then "blocked"
    when 429 then "rate_limited"
    else "rejected"
    end
    raise Error, code
  rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, JSON::ParserError, Net::HTTPBadResponse, Net::ProtocolError
    # The URL contains the bot token; Telegram's response may contain message text.
    # Never propagate either into a job's exception log.
    raise Error.new("unknown"), cause: nil
  end
  private_class_method :request
end
