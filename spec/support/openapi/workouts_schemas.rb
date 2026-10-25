# frozen_string_literal: true

# OpenAPI schemas for workouts, integrations and Strava (spec/requests/api/v1).
module WorkoutsSchemas
  NULLABLE_STRING = { type: :string, nullable: true }.freeze
  NULLABLE_INTEGER = { type: :integer, nullable: true }.freeze

  WORKOUT = {
    type: :object,
    required: %w[id sport workout_date distance_km duration pace_seconds_per_km start_time start_time_known provider external_id created_at],
    properties: {
      id: { type: :integer },
      sport: { type: :string, nullable: true, example: "run" },
      workout_date: { type: :string, format: :date, nullable: true },
      distance_km: { type: :number, nullable: true },
      duration: {
        type: :object,
        required: %w[minutes moving_seconds elapsed_seconds],
        properties: { minutes: NULLABLE_INTEGER, moving_seconds: NULLABLE_INTEGER, elapsed_seconds: NULLABLE_INTEGER }
      },
      pace_seconds_per_km: { **NULLABLE_INTEGER, description: "Seconds per km; null without distance or time" },
      start_time: { **NULLABLE_STRING, example: "07:30", description: "Local wall-clock time; null when unknown" },
      start_time_known: { type: :boolean },
      provider: { type: :string, enum: %w[manual strava] },
      external_id: { **NULLABLE_STRING, description: "The Strava activity id for imports" },
      created_at: { type: :string, format: "date-time" }
    }
  }.freeze

  WORKOUT_INPUT = {
    type: :object,
    required: [ "workout" ],
    properties: {
      workout: {
        type: :object,
        required: %w[sport workout_date duration_seconds],
        properties: {
          sport: { type: :string, enum: Workout::SPORTS },
          workout_date: { type: :string, format: :date },
          start_time: { type: :string, pattern: "^([01]?[0-9]|2[0-3]):[0-5][0-9]$", example: "07:30" },
          distance_km: { type: :number, minimum: 0 },
          duration_seconds: { type: :integer, minimum: 1 }
        }
      }
    }
  }.freeze

  INTEGRATION = {
    type: :object,
    required: %w[provider connected athlete_id scope connected_at],
    properties: {
      provider: { type: :string, enum: [ "strava" ] },
      connected: { type: :boolean },
      athlete_id: NULLABLE_INTEGER,
      scope: { **NULLABLE_STRING, example: "read,activity:read_all" },
      connected_at: { type: :string, format: "date-time", nullable: true }
    }
  }.freeze

  STRAVA_ACTIVITY = {
    type: :object,
    required: %w[id name sport_type sport importable imported distance_km moving_time_seconds start_date start_date_local],
    properties: {
      id: { type: :string },
      name: NULLABLE_STRING,
      sport_type: { type: :string, example: "TrailRun" },
      sport: { **NULLABLE_STRING, description: "The app's sport; null when not tracked" },
      importable: { type: :boolean },
      imported: { type: :boolean },
      distance_km: { type: :number },
      moving_time_seconds: { type: :integer },
      start_date: { type: :string, format: "date-time", nullable: true },
      start_date_local: { **NULLABLE_STRING, example: "2026-05-10T08:00:00", description: "Local wall-clock time, no zone" }
    }
  }.freeze
end
