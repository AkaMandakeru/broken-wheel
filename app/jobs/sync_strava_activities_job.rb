# frozen_string_literal: true

# Imports a player's Strava history (or everything since `after`). A full
# history can run to dozens of pages, so the job is a continuation: the page
# it reached is saved with the job, and a run cut short by a deploy or a dyno
# restart picks up from there instead of starting over.
class SyncStravaActivitiesJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :default

  # Errors go to the retry_on rules below rather than Continuable's immediate
  # resume: a rate-limited import must wait out Strava's window. The retry
  # still carries the saved page.
  self.resume_errors_after_advancing = false

  discard_on ActiveRecord::RecordNotFound
  # Handlers are matched last-declared first, so the subclass goes below.
  retry_on StravaService::Error, wait: :polynomially_longer, attempts: 3
  retry_on StravaService::RateLimitError, wait: 15.minutes, attempts: 5

  def perform(user_id, after: nil)
    user = User.find(user_id)
    return unless user.connected_to_strava?

    step :import, start: 1 do |step|
      Strava::ActivityImporter.new(user, after: after).call(from_page: step.cursor) { |page| step.set!(page) }
    end
  rescue StravaService::AuthError => e
    Rails.logger.warn("Strava sync aborted for user=#{user_id}: #{e.message}")
  end
end
