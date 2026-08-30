require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # kamal-proxy terminates TLS and forwards plain HTTP, so the only evidence a request arrived
  # securely is X-Forwarded-Proto. Without this Rails treats every request as insecure: it builds
  # http:// URLs into password-reset mail and drops the `secure` flag from the session cookie.
  config.assume_ssl = true

  # Redirects http:// to https:// and sends HSTS. On this app a plain-HTTP request is not a
  # cosmetic problem: a student's /t/:token link is their only credential and it rides in the
  # request path, in the clear, for anyone on the same classroom Wi-Fi.
  config.force_ssl = true

  # kamal-proxy health-checks the container over plain HTTP on the internal network, and a 301
  # is not a passing health check — an unexcluded /up fails every deploy.
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Host for links in mailer templates. https, because force_ssl above would bounce an http://
  # reset link anyway and the redirect is one more hop for a teacher already locked out.
  # Delivery itself is still unconfigured — see docs/deploy.md § Known gaps.
  config.action_mailer.default_url_options = { host: "edubba.com.ua", protocol: "https" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Answer only to the name the certificate is issued for. No subdomain pattern: nothing is
  # served off one, and a wildcard would accept a Host header for a name that does not exist.
  # Adding www means adding it here, to proxy.host in config/deploy.yml, and to DNS — all three.
  config.hosts = [ "edubba.com.ua" ]

  # Same reason as ssl_options above: the proxy's health check arrives with the container's own
  # Host, which is never the domain, so /up has to sit outside this check or deploys fail.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
