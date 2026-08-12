# frozen_string_literal: true

# One daily challenge offered to one user on one day. Rows are durable: XP is
# recomputed from them, so completing a daily is never lost to a later recalc.
class DailyChallengeAssignment < ApplicationRecord
  belongs_to :user
  belongs_to :season
  belongs_to :daily_challenge_template

  delegate :metric, :target, :options, :sport, :display_title, :display_description,
           :percent_of, :satisfied_by?, to: :daily_challenge_template

  scope :completed, -> { where.not(completed_at: nil) }
  scope :pending, -> { where(completed_at: nil) }
  scope :on, ->(date) { where(challenge_date: date) }
  scope :for_season, ->(season) { where(season_id: season.id) }

  def completed?
    completed_at.present?
  end

  # The single day this assignment covers, as a date range for metric windows.
  def window
    challenge_date..challenge_date
  end

  # Current value of this daily's metric, measured over its own day.
  #
  # Lives here so the evaluator and the season page ask the same question the
  # same way — the mapping from an assignment to a metric scope belongs with the
  # assignment, not duplicated in each caller.
  def progress_in(context)
    ChallengeMetrics.call(
      metric,
      context.rescope(window: window, options: options || {}, sport: sport.presence)
    )
  end

  def xp_reward
    daily_challenge_template.xp_reward
  end

  def coin_reward
    daily_challenge_template.coin_reward
  end
end
