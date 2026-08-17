# frozen_string_literal: true

# Posts one message to a Slack incoming webhook.
#
# Takes the *event key*, not the URL: Solid Queue stores job arguments as text
# in the database, so passing the webhook would write a live credential into
# `solid_queue_jobs.arguments` and into every job log line. The URL is resolved
# from the environment here, at the moment of sending.
#
# Failures are logged and swallowed rather than retried forever: a notification
# is not worth a poison-pill job, and a signup must never fail because Slack is
# down.
class SlackDeliveryJob < ApplicationJob
  queue_as :default

  TIMEOUT = 5

  def perform(event_key, payload)
    webhook_url = Slack::Config.webhook_url_for(event_key)
    return if webhook_url.blank?

    response = post(webhook_url, payload)
    return if response.is_a?(Net::HTTPSuccess)

    # Slack answers with a plain-text reason (invalid_payload, channel_not_found,
    # no_service). Worth logging — never the URL.
    Rails.logger.warn("Slack delivery failed for #{event_key}: #{response.code} #{response.body.to_s.truncate(200)}")
  rescue StandardError => e
    Rails.logger.warn("Slack delivery error for #{event_key}: #{e.class}: #{e.message}")
  end

  private

  def post(webhook_url, payload)
    uri = URI.parse(webhook_url)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                            open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(request)
    end
  end
end
