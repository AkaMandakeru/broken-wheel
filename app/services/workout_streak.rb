# frozen_string_literal: true

# Longest run of consecutive calendar weeks in which the user ran at least once.
#
# This is the one piece of the retired badge engine that outlived it: season XP
# still pays out on weekly consistency, so the math had to keep a home once
# AchievementChecker went away.
class WorkoutStreak
  WEEK_START = :sunday

  def self.weeks_for(user)
    new(user).weeks
  end

  def initialize(user)
    @user = user
  end

  def weeks
    weeks_run = @user.workouts
                     .where(sport: "run")
                     .where.not(workout_date: nil)
                     .pluck(:workout_date)
                     .map { |date| date.beginning_of_week(WEEK_START) }
                     .uniq
                     .sort

    return 0 if weeks_run.empty?

    longest = 1
    current = 1

    weeks_run.each_cons(2) do |previous, following|
      current = ((following - previous).to_i == 7) ? current + 1 : 1
      longest = [ longest, current ].max
    end

    longest
  end
end
