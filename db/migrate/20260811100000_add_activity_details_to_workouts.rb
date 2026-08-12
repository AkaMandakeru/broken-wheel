# frozen_string_literal: true

# Time-of-day, elevation and effort details for workouts. Without these, an
# entire class of challenges ("run before 05:30", "most elevation", "finish
# without stopping") cannot be evaluated at all.
class AddActivityDetailsToWorkouts < ActiveRecord::Migration[8.1]
  def change
    add_column :workouts, :started_at_local, :datetime
    add_column :workouts, :started_at, :datetime

    # Manual workouts carry no clock time. Without this flag they would silently
    # satisfy hour-based challenges by defaulting to midnight.
    add_column :workouts, :start_time_known, :boolean, default: false, null: false

    # Minutes since local midnight (0..1439). Strava serialises start_date_local
    # as a wall clock with a bogus "Z" suffix, so any timezone conversion on the
    # datetime shifts it. This integer is computed once and never moves, which
    # is what "run before 05:30" must compare against.
    add_column :workouts, :start_minute_of_day, :integer

    add_column :workouts, :elevation_gain_m, :decimal, precision: 8, scale: 1
    add_column :workouts, :calories, :integer
    add_column :workouts, :moving_time_seconds, :integer
    add_column :workouts, :elapsed_time_seconds, :integer

    # Digest of the GPS summary polyline — lets "run a new route" compare routes
    # without storing the full track.
    add_column :workouts, :route_signature, :string

    add_index :workouts, [ :user_id, :started_at_local ]
    add_index :workouts, [ :user_id, :workout_date ]
  end
end
