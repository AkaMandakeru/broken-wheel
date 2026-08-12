# frozen_string_literal: true

module ChallengeMetrics
  module Metrics
    # A metric answers one question about a preloaded set of workouts.
    # Subclasses implement `.call(context)` and return a Numeric.
    class Base
      class << self
        def call(_context)
          raise NotImplementedError, "#{name} must implement .call"
        end

        # Display unit; drives pluralisation and formatting in the UI.
        def unit
          "count"
        end

        # :gte — "reach at least N" (the default).
        # :lte — "get under N", for time and pace goals.
        def comparator
          :gte
        end

        # Metrics that read the clock can only be satisfied by workouts with a
        # trustworthy start time.
        def requires_start_time?
          false
        end

        private

        # Workouts whose clock time is trustworthy. Manual entries without a
        # recorded time must never satisfy an hour-based goal.
        def timed(context)
          context.workouts.select { |w| w.start_time_known? && w.start_minute_of_day.present? }
        end
      end
    end
  end
end
