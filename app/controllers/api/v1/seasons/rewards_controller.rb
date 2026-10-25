# frozen_string_literal: true

module Api
  module V1
    module Seasons
      # The battle pass, one entry per level with its free and premium slot,
      # and the bonus rewards earned along other tracks.
      class RewardsController < BaseController
        allow_unauthenticated_access only: :index

        def index
          granted_ids = dashboard.granted_reward_ids
          return unless stale_section?(@season.season_rewards.maximum(:updated_at), granted_ids)

          participation = dashboard.participation
          render_data({
            premium: participation&.premium? || false,
            current_level: participation&.level,
            levels: (1..@season.max_level).map { |level| level_entry(level, granted_ids, participation) },
            bonus: serialize(dashboard.bonus_rewards, granted_ids)
          })
        end

        private

        def level_entry(level, granted_ids, participation)
          rewards = dashboard.rewards_by_level[level] || []
          {
            level: level,
            reached: participation.present? && participation.level >= level,
            free: serialize(rewards.find { |reward| reward.track == "free" }, granted_ids),
            premium: serialize(rewards.find { |reward| reward.track == "premium" }, granted_ids)
          }
        end

        def serialize(rewards, granted_ids)
          return nil if rewards.nil?

          SeasonRewardResource.new(rewards, params: { granted_ids: granted_ids }).serializable_hash
        end
      end
    end
  end
end
