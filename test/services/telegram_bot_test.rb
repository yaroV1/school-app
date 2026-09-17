require "test_helper"

class TelegramBotTest < ActiveSupport::TestCase
  setup do
    @settings = Rails.application.config.x.telegram
    Rails.application.config.x.telegram = ActiveSupport::OrderedOptions.new.update(
      bot_token: "test-token", bot_username: "school_test_bot", webhook_secret: "webhook-test-secret",
      app_url: "https://school.example")
  end

  teardown do
    Rails.application.config.x.telegram = @settings
  end

  test "sendMessage uses a private numeric recipient and disables link previews" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { '{"ok":true,"result":{"message_id":1}}' }
    http = Object.new
    sent_request = nil
    connection = nil
    http.define_singleton_method(:request) { |request| sent_request = request; response }
    replacing(Net::HTTP, :start, ->(host, port, **options, &block) {
      connection = [ host, port, options ]
      block.call(http)
    }) do
      TelegramBot.send_message(chat_id: 123456789012, text: "Private URL")
    end
    assert_equal "api.telegram.org", connection[0]
    assert_equal 443, connection[1]
    assert_equal true, connection[2][:use_ssl]
    assert_equal 10, connection[2][:read_timeout]
    assert_equal "POST", sent_request.method
    assert_equal "/bottest-token/sendMessage", sent_request.path
    assert_equal({ "chat_id" => 123456789012, "text" => "Private URL", "link_preview_options" => { "is_disabled" => true } }, JSON.parse(sent_request.body))
  end

  test "webhook setup posts its secret without dropping pending updates" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { '{"ok":true,"result":true}' }
    http = Object.new
    sent_request = nil
    http.define_singleton_method(:request) { |request| sent_request = request; response }
    replacing(Net::HTTP, :start, ->(*, **, &block) { block.call(http) }) do
      TelegramBot.set_webhook
    end
    assert_equal "/bottest-token/setWebhook", sent_request.path
    assert_equal({ "url" => "https://school.example/telegram/webhook", "secret_token" => "webhook-test-secret",
      "allowed_updates" => [ "message" ], "max_connections" => 1 }, JSON.parse(sent_request.body))
  end

  test "errors never expose the response body bot token or uncertain private URL" do
    [ [ 403, "blocked" ], [ 429, "rate_limited" ], [ 400, "rejected" ] ].each do |status, expected|
      response = Net::HTTPBadRequest.new("1.1", status.to_s, "Failed")
      response.define_singleton_method(:body) { { ok: false, error_code: status, description: "test-token Private URL" }.to_json }
      http = Object.new
      http.define_singleton_method(:request) { |_| response }
      replacing(Net::HTTP, :start, ->(*, **, &block) { block.call(http) }) do
        error = assert_raises(TelegramBot::Error) { TelegramBot.send_message(chat_id: 123, text: "Private URL") }
        assert_equal expected, error.code
        assert_not_includes error.full_message, "test-token"
        assert_not_includes error.full_message, "Private URL"
      end
    end
    replacing(Net::HTTP, :start, ->(*, **) { raise Net::ReadTimeout, "test-token Private URL" }) do
      error = assert_raises(TelegramBot::Error) { TelegramBot.send_message(chat_id: 123, text: "Private URL") }
      assert_equal "unknown", error.code
      assert_nil error.cause
      assert_not_includes error.full_message, "test-token"
      assert_not_includes error.full_message, "Private URL"
    end
  end

  test "missing configuration refuses network calls and class payload fits Telegram limit" do
    group = users(:one).class_groups.create!(name: "Class")
    assert_match(/\A[A-Za-z0-9_-]{1,64}\z/, group.telegram_join_token)
    assert_equal "https://t.me/school_test_bot?start=#{group.telegram_join_token}", TelegramBot.join_url(group)
    TelegramBot.settings.bot_token = nil
    assert_not TelegramBot.configured?
    replacing(Net::HTTP, :start, ->(*, **) { raise "unconfigured network request" }) do
      assert_raises(TelegramBot::Error) { TelegramBot.send_message(chat_id: 123, text: "Private URL") }
    end
  end
end
