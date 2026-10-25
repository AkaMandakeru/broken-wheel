# frozen_string_literal: true

module Strava
  # Imports the Strava activities a player picked from the preview list. The
  # web runs it inline; the app's request enqueues ImportStravaActivitiesJob,
  # which runs this too, so both report the same analytics and Slack events.
  #
  # Strava errors (StravaService::AuthError, RateLimitError, Error) propagate:
  # the web turns them into a flash, the job retries or gives up.
  class ManualImport
    def initialize(user, activity_ids, client: nil)
      @user = user
      @activity_ids = Array(activity_ids).map(&:to_s).compact_blank.uniq
      @client = client
    end

    # Returns how many activities became new or updated workouts.
    def call
      client = @client || StravaService.new(@user)
      importer = Strava::ActivityImporter.new(@user, client: client)

      Analytics.track(user: @user, event: "workout_import_started",
                      properties: { provider: "strava", requested_count: @activity_ids.size })

      imported = @activity_ids.count { |strava_id| importer.import_one(client.activity(strava_id)) }

      Analytics.track(user: @user, event: "workout_import_completed",
                      properties: { provider: "strava", imported_count: imported,
                                    requested_count: @activity_ids.size,
                                    season_key: Season.active.by_recent.first&.key })

      # One message per import, not per workout — a 40-activity import should
      # not produce 40 Slack notifications.
      if imported.positive?
        SlackNotifier.notify(:workout_imported, user: @user,
                                                extra: { "Workouts" => imported, "Source" => "Strava" })
      end

      imported
    end
  end
end
