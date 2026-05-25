# frozen_string_literal: true

require "posthog"

POSTHOG_CLIENT = if ENV["POSTHOG_API_KEY"].present?
  PostHog::Client.new(
    api_key: ENV.fetch("POSTHOG_API_KEY"),
    host: ENV.fetch("POSTHOG_HOST", "https://us.i.posthog.com"),
    on_error: ->(status, msg) { Rails.logger.warn("PostHog error: #{status} — #{msg}") }
  )
end
