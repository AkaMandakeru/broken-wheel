# frozen_string_literal: true

class SyncStravaActivitiesJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on StravaService::RateLimitError, wait: 15.minutes, attempts: 5
  retry_on StravaService::Error, wait: :polynomially_longer, attempts: 3

  def perform(user_id, after: nil)
    user = User.find(user_id)
    return unless user.connected_to_strava?

    Strava::ActivityImporter.new(user, after: after).call
  rescue StravaService::AuthError => e
    Rails.logger.warn("Strava sync aborted for user=#{user_id}: #{e.message}")
  end
end
