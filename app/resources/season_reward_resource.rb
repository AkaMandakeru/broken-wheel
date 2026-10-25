# frozen_string_literal: true

# A battle-pass or bonus reward. Param `granted_ids` lists the ones the viewer
# has received.
class SeasonRewardResource < ApplicationResource
  attributes :id, :level, :track, :reward_type, :reward_key, :unlock_kind, :unlock_value, :coins

  attribute(:label) { |reward| reward.label }
  attribute(:unlock_label) { |reward| reward.unlock_label }
  attribute(:premium) { |reward| reward.premium? }
  attribute(:granted) { |reward| Array(params[:granted_ids]).include?(reward.id) }
end
