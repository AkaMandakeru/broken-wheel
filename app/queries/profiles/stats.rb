# frozen_string_literal: true

module Profiles
  # The profile is a season record: what the player has run, and the medal each
  # season they entered ended with. Read by the profile page and GET /api/v1/me/stats.
  #
  #   stats = Profiles::Stats.new(user)
  #   stats.to_h          # => { distance_km: 42.0, week_streak: 3, workouts: 9, seasons: 2, medals: 1 }
  #   stats.participations
  class Stats
    attr_reader :user

    def initialize(user)
      @user = user
    end

    def participations
      @participations ||= user.season_history.to_a
    end

    def medals
      @medals ||= participations.select(&:medal_tier)
    end

    # Which seasons in the history can still be opened, so a card links only
    # where there is a page to land on.
    def browsable_season_ids
      @browsable_season_ids ||= Season.browsable.pluck(:id).to_set
    end

    def distance_km = user.workouts.sum(:distance_km).to_f.round(1)

    def week_streak = WorkoutStreak.weeks_for(user)

    def workouts = user.workouts.count

    def to_h
      @to_h ||= {
        distance_km: distance_km,
        week_streak: week_streak,
        workouts: workouts,
        seasons: participations.size,
        medals: medals.size
      }
    end
  end
end
