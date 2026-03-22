# frozen_string_literal: true

class AchievementsController < ApplicationController
  before_action :authenticate_user!

  def index
    @earned_map = current_user.user_badges.includes(:badge).index_by(&:badge_id)
    @total_points = @earned_map.values.sum { |ub| ub.badge.points }
    @earned_count = @earned_map.size
    @total_count = Badge.where(badge_type: Badge::CATEGORIES.keys).count

    @workout_count_badges  = Badge.workout_count
    @distance_pr_badges    = Badge.distance_pr
    @distance_count_badges = Badge.distance_count
    @streak_badges         = Badge.streak
    @pace_badges           = Badge.pace

    stats = AchievementChecker.user_stats(current_user)
    @progress_map = build_progress_map(stats)
  end

  private

  def build_progress_map(stats)
    map = {}
    Badge.where(badge_type: Badge::CATEGORIES.keys).each do |badge|
      map[badge.id] = compute_progress(badge, stats)
    end
    map
  end

  def compute_progress(badge, stats)
    case badge.badge_type
    when "workout_count"
      current = stats[:workout_count]
      max     = badge.threshold_value.to_i
      { current: current, max: max, pct: pct(current, max),
        label: "#{current} / #{max} runs", kind: :bar }

    when "distance_pr"
      count = stats[:distance_counts][badge.threshold_distance.to_i] || 0
      { current: count >= 1 ? 1 : 0, max: 1, pct: count >= 1 ? 100 : 0,
        label: count >= 1 ? "Reached!" : "Never reached #{badge.threshold_distance.to_i}km yet",
        kind: :binary }

    when "distance_count"
      current = stats[:distance_counts][badge.threshold_distance.to_i] || 0
      max     = badge.threshold_value.to_i
      { current: current, max: max, pct: pct(current, max),
        label: "#{current} / #{max} runs at #{badge.threshold_distance.to_i}km+", kind: :bar }

    when "streak"
      current = stats[:streak]
      max     = badge.threshold_value.to_i
      { current: current, max: max, pct: pct(current, max),
        label: "#{current} / #{max} consecutive weeks", kind: :bar }

    when "pace"
      best      = stats[:paces][badge.threshold_distance.to_i]
      threshold = badge.threshold_value.to_f
      if best
        { current: best, max: threshold, pct: [ (threshold / best * 100).round, 100 ].min,
          label: "Best: #{fmt_pace(best)} → Need: ≤ #{fmt_pace(threshold)}", kind: :pace }
      else
        { current: nil, max: threshold, pct: 0,
          label: "No runs at #{badge.threshold_distance.to_i}km yet → Need: ≤ #{fmt_pace(threshold)}",
          kind: :pace }
      end
    end
  end

  def pct(current, max)
    return 0 if max.zero?
    [ (current.to_f / max * 100).round, 100 ].min
  end

  def fmt_pace(pace)
    return "–" if pace.nil?
    minutes = pace.to_i
    seconds = ((pace % 1) * 60).round
    "#{minutes}:#{seconds.to_s.rjust(2, '0')}/km"
  end
end
