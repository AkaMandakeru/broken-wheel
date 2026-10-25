# frozen_string_literal: true

# One of today's daily challenges. Param `progress`
# ({ assignment => value }, from Seasons::Dashboard#daily_progress) carries the
# live value, so the bar moves before the next recalculation.
class SeasonDailyResource < ApplicationResource
  attributes :id, :metric, :sport, :xp_reward, :coin_reward

  attribute(:key) { |assignment| assignment.daily_challenge_template.key }
  attribute(:title) { |assignment| assignment.display_title }
  attribute(:description) { |assignment| assignment.display_description }
  attribute(:target) { |assignment| assignment.target.to_f }
  attribute(:challenge_date) { |assignment| assignment.challenge_date.iso8601 }
  attribute(:completed) { |assignment| assignment.completed? }
  attribute(:completed_at) { |assignment| assignment.completed_at&.iso8601 }
  attribute(:value) { |assignment| params[:progress]&.dig(assignment)&.to_f }
  attribute(:percent) { |assignment| assignment.percent_of(params[:progress]&.dig(assignment)) }
end
