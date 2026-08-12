# frozen_string_literal: true

module Seasons
  # Rolls every participant's workouts into a single community total.
  #
  # Unlike ChallengeMetrics (which answers per-user questions from preloaded
  # rows), this aggregates in SQL across the whole season — the totals are far
  # too large to load into memory.
  class CommunityAggregator
    # Metrics that can be summed across users. Per-user shapes like streaks or
    # personal records have no community meaning.
    AGGREGATABLE = {
      "distance_km"      => "COALESCE(SUM(distance_km), 0)",
      "activity_count"   => "COUNT(*)",
      "elevation_gain_m" => "COALESCE(SUM(elevation_gain_m), 0)",
      "calories"         => "COALESCE(SUM(calories), 0)",
      "active_days"      => "COUNT(DISTINCT workout_date)"
    }.freeze

    def self.call(goal)
      new(goal).call
    end

    def initialize(goal)
      @goal = goal
      @season = goal.season
    end

    def call
      expression = AGGREGATABLE[@goal.metric]
      return @goal.current_value unless expression

      total = scope.pick(Arel.sql(expression)).to_f.round(2)
      @goal.update!(current_value: total, computed_at: Time.current)
      total
    end

    private

    # Only workouts by people actually taking part in the season count toward
    # its community goal.
    def scope
      participant_ids = @season.season_participations.select(:user_id)
      relation = Workout.where(user_id: participant_ids)
      window = @season.date_window
      window ? relation.where(workout_date: window) : relation
    end
  end
end
