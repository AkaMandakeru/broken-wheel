# frozen_string_literal: true

require "posthog"

POSTHOG_CLIENT = if ENV["POSTHOG_API_KEY"].present? && (Rails.env.production? || ENV["POSTHOG_ENABLED"] == "true")
  PostHog::Client.new(
    api_key: ENV.fetch("POSTHOG_API_KEY"),
    host: ENV.fetch("POSTHOG_HOST", "https://us.i.posthog.com"),
    on_error: ->(status, msg) { Rails.logger.warn("PostHog error: #{status} — #{msg}") }
  )
end

# Say at boot whether analytics actually leaves the building.
#
# Analytics.track swallows its own errors by design — a tracking failure must
# never break the flow it sits in — so a season running with PostHog switched
# off looks exactly like one running with it on, right up until the funnels turn
# out to be empty at the end of the month it was meant to measure. Events always
# reach the analytics_events table either way; this is only about the fan-out.
Rails.application.config.after_initialize do
  if POSTHOG_CLIENT
    Rails.logger.info("PostHog: enabled — sending to #{ENV.fetch('POSTHOG_HOST', 'https://us.i.posthog.com')}")
  elsif ENV["POSTHOG_API_KEY"].blank?
    Rails.logger.warn("PostHog: disabled — POSTHOG_API_KEY is not set. Events go to analytics_events only.")
  else
    Rails.logger.warn("PostHog: disabled — outside production this needs POSTHOG_ENABLED=true. Events go to analytics_events only.")
  end
end
