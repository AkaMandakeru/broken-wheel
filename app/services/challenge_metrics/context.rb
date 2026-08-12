# frozen_string_literal: true

module ChallengeMetrics
  # Everything a metric needs to answer "what is the value of X for this user in
  # this window", with the workouts loaded exactly once.
  #
  # This preloading is the whole reason the class exists: a season recalculation
  # evaluates ~20 metrics across ~20 challenges, and a metric that issued its own
  # query would turn one recalc into several hundred round trips.
  class Context
    attr_reader :user, :window, :options, :season, :sport, :participation

    def initialize(user:, window:, options: {}, season: nil, sport: nil, participation: nil, scoped_workouts: nil, history: nil)
      @user = user
      @window = window
      @options = (options || {}).symbolize_keys
      @season = season
      @sport = sport
      @participation = participation
      @scoped_workouts = scoped_workouts
      @history = history
    end

    # Reuses this context's loaded history for a different window/options —
    # how a single recalculation serves many challenges with one DB read.
    def rescope(window: @window, options: {}, sport: :unchanged, participation: @participation)
      self.class.new(
        user: user,
        window: window,
        options: options,
        season: season,
        sport: sport == :unchanged ? @sport : sport,
        participation: participation,
        history: history
      )
    end

    # Every workout the user has ever logged, ordered oldest first. Loaded once
    # and shared across every metric and challenge in a recalculation.
    def history
      @history ||= user.workouts.order(:workout_date, :start_minute_of_day).to_a
    end

    # History narrowed to this challenge's window and sport.
    def workouts
      @scoped_workouts ||= begin
        list = window ? history.select { |w| in_window?(w) } : []
        sport.present? ? list.select { |w| w.sport == sport } : list
      end
    end

    # Everything before the window starts — what a personal record is measured against.
    def workouts_before_window
      @workouts_before_window ||= begin
        return [] if window.nil?

        list = history.select { |w| w.workout_date.present? && w.workout_date < window_start }
        sport.present? ? list.select { |w| w.sport == sport } : list
      end
    end

    def window_start
      @window_start ||= window && to_date(window.begin)
    end

    def window_end
      @window_end ||= window && to_date(window.end)
    end

    def dates
      @dates ||= workouts.filter_map(&:workout_date).uniq.sort
    end

    # Total distance per calendar day, used by day-over-day comparisons.
    def distance_by_date
      @distance_by_date ||= workouts.group_by(&:workout_date)
                                    .transform_values { |ws| ws.sum { |w| w.distance_km.to_f } }
    end

    def option(key, default = nil)
      options.fetch(key, default)
    end

    private

    def in_window?(workout)
      date = workout.workout_date
      return false if date.nil?

      date >= window_start && date <= window_end
    end

    def to_date(value)
      value.respond_to?(:to_date) ? value.to_date : value
    end
  end
end
