# frozen_string_literal: true

class Analytics
  def self.track(user:, event:, properties: {})
    AnalyticsEvent.create!(
      user: user,
      event_name: event,
      properties: properties
    )

    if defined?(POSTHOG_CLIENT) && POSTHOG_CLIENT
      POSTHOG_CLIENT.capture(
        distinct_id: user.id.to_s,
        event: event,
        properties: properties.merge(
          email: user.email,
          name: "#{user.first_name} #{user.last_name}"
        )
      )
    end
  rescue StandardError => e
    Rails.logger.error("Analytics.track failed: #{e.class}: #{e.message}")
  end

  def self.identify(user:)
    return unless defined?(POSTHOG_CLIENT) && POSTHOG_CLIENT

    POSTHOG_CLIENT.identify(
      distinct_id: user.id.to_s,
      properties: {
        email: user.email,
        name: "#{user.first_name} #{user.last_name}",
        created_at: user.created_at&.iso8601
      }
    )
  rescue StandardError => e
    Rails.logger.error("Analytics.identify failed: #{e.class}: #{e.message}")
  end
end
