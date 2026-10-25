# frozen_string_literal: true

# A recent Strava activity in the import preview. `importable` is false for
# sports the app doesn't track; `imported` once it is already a workout.
class StravaActivityResource < ApplicationResource
  attribute(:id) { |activity| activity.id.to_s }
  attributes :name, :sport_type

  attribute(:sport) { |activity| Strava::ActivityImporter::SPORT_MAP[activity.sport_type] }
  attribute(:importable) { |activity| Strava::ActivityImporter::SPORT_MAP.key?(activity.sport_type) }
  attribute(:imported) { |activity| params[:imported_ids].to_set.include?(activity.id.to_s) }
  attribute(:distance_km) { |activity| (activity.distance.to_f / 1000).round(2) }
  attribute(:moving_time_seconds) { |activity| activity.moving_time.to_i }
  attribute(:start_date) { |activity| activity.start_date&.iso8601 }
  # Strava's local time is wall-clock time with a misleading "Z"; sent without a zone.
  attribute(:start_date_local) { |activity| (activity.start_date_local || activity.start_date)&.strftime("%Y-%m-%dT%H:%M:%S") }
end
