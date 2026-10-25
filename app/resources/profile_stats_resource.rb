# frozen_string_literal: true

# The numbers on the profile header: a Profiles::Stats.
class ProfileStatsResource < ApplicationResource
  attribute(:distance_km) { |stats| stats.to_h[:distance_km] }
  attribute(:week_streak) { |stats| stats.to_h[:week_streak] }
  attribute(:workouts) { |stats| stats.to_h[:workouts] }
  attribute(:seasons) { |stats| stats.to_h[:seasons] }
  attribute(:medals) { |stats| stats.to_h[:medals] }
end
