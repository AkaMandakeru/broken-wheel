# frozen_string_literal: true

class AchievementChecker
  def initialize(user)
    @user = user
  end

  # Returns a hash of current user stats needed to compute progress for any badge
  def self.user_stats(user)
    new(user).user_stats
  end

  def user_stats
    running = running_workouts

    counts_by_distance = {}
    [ 3, 5, 8, 10, 15, 20, 21, 25, 30, 40, 42, 50 ].each do |d|
      counts_by_distance[d] = running.where("distance_km >= ?", d).count
    end

    paces_by_distance = {}
    [ 5, 10, 21 ].each do |d|
      paces_by_distance[d] = running
        .where("distance_km >= ? AND duration_minutes > 0 AND distance_km > 0", d)
        .minimum("duration_minutes::float / distance_km::float")
    end

    {
      workout_count:    running.count,
      streak:           calculate_max_streak,
      distance_counts:  counts_by_distance,
      paces:            paces_by_distance
    }
  end

  # Returns array of newly awarded UserBadge records
  def check_all!
    [
      check_workout_count!,
      check_distance_prs!,
      check_distance_counts!,
      check_streaks!,
      check_paces!
    ].flatten.compact
  end

  private

  def running_workouts
    @running_workouts ||= @user.workouts.where(sport: "run")
  end

  # --- Workout Count ---
  def check_workout_count!
    count = running_workouts.count
    Badge.where(badge_type: "workout_count")
         .where("threshold_value <= ?", count)
         .map { |badge| award!(badge) }
  end

  # --- Distance PR (first time reaching a distance) ---
  def check_distance_prs!
    Badge.where(badge_type: "distance_pr").map do |badge|
      next unless running_workouts.where("distance_km >= ?", badge.threshold_distance).exists?
      award!(badge)
    end
  end

  # --- Distance Count (N times at a given distance) ---
  def check_distance_counts!
    Badge.where(badge_type: "distance_count").map do |badge|
      count = running_workouts.where("distance_km >= ?", badge.threshold_distance).count
      next unless count >= badge.threshold_value
      award!(badge)
    end
  end

  # --- Weekly Streak (consecutive calendar weeks with at least one run) ---
  def check_streaks!
    streak = calculate_max_streak
    Badge.where(badge_type: "streak")
         .where("threshold_value <= ?", streak)
         .map { |badge| award!(badge) }
  end

  # --- Pace (run distance at pace ≤ threshold) ---
  def check_paces!
    Badge.where(badge_type: "pace").map do |badge|
      # pace (min/km) = duration_minutes / distance_km — lower is faster
      qualifying = running_workouts
        .where("distance_km >= ? AND duration_minutes > 0 AND distance_km > 0", badge.threshold_distance)
        .where("(duration_minutes::float / distance_km::float) <= ?", badge.threshold_value)
        .exists?
      next unless qualifying
      award!(badge)
    end
  end

  # ---

  def award!(badge)
    return nil if @user.user_badges.exists?(badge: badge)
    @user.user_badges.create!(badge: badge, earned_at: Time.current)
  end

  def calculate_max_streak
    dates = running_workouts
      .where.not(workout_date: nil)
      .pluck(:workout_date)
      .map { |d| Date.commercial(d.year, d.cweek, 1) } # normalize to Monday of each week
      .uniq
      .sort

    return 0 if dates.empty?

    max = 1
    current = 1

    dates.each_cons(2) do |a, b|
      if (b - a).to_i == 7
        current += 1
        max = [max, current].max
      else
        current = 1
      end
    end

    max
  end
end
