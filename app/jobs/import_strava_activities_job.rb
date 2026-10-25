# frozen_string_literal: true

# The app's "import these" request: the same import the web runs inline
# (Strava::ManualImport), moved off the request so a long selection can't time
# out on a phone connection.
class ImportStravaActivitiesJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  # Handlers are matched last-declared first, so the subclass goes below.
  retry_on StravaService::Error, wait: :polynomially_longer, attempts: 3
  retry_on StravaService::RateLimitError, wait: 15.minutes, attempts: 5

  def perform(user_id, activity_ids)
    user = User.find(user_id)
    return unless user.connected_to_strava?

    Strava::ManualImport.new(user, activity_ids).call
  rescue StravaService::AuthError => e
    Rails.logger.warn("Strava import aborted for user=#{user_id}: #{e.message}")
  end
end
