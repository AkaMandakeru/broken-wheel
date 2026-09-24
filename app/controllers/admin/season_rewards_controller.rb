# frozen_string_literal: true

module Admin
  class SeasonRewardsController < BaseController
    def create
      @season = Season.find(params[:season_id])
      reward = @season.season_rewards.new(season_reward_params)
      if reward.save
        redirect_to admin_season_path(@season), notice: t("admin.flashes.season_rewards.added")
      else
        redirect_to admin_season_path(@season), alert: reward.errors.full_messages.to_sentence
      end
    end

    # Hands an existing participation reward to everyone who already qualifies.
    # The automatic path only reaches someone when they are recalculated, which
    # for a reward added mid-season can be never.
    def distribute
      @season = Season.find(params[:season_id])
      reward = @season.season_rewards.find(params[:id])

      # A claimable reward belongs to the player to take; pushing it would empty
      # the locker's Claim button of its purpose.
      unless reward.participation? && !reward.claimable?
        return redirect_to admin_season_path(@season),
                           alert: t("admin.flashes.season_rewards.not_distributable")
      end

      DistributeSeasonRewardJob.perform_later(reward.id)
      redirect_to admin_season_path(@season), notice: t("admin.flashes.season_rewards.distributing")
    end

    def destroy
      @season = Season.find(params[:season_id])
      @season.season_rewards.find_by(id: params[:id])&.destroy
      redirect_to admin_season_path(@season), notice: t("admin.flashes.season_rewards.removed")
    end

    private

    def season_reward_params
      params.require(:season_reward).permit(:level, :reward_type, :reward_key, :name,
                                            :track, :coins, :unlock_kind, :unlock_value, :position,
                                            :joined_from, :joined_until, :claimable)
    end
  end
end
