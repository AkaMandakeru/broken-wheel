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

    def destroy
      @season = Season.find(params[:season_id])
      @season.season_rewards.find_by(id: params[:id])&.destroy
      redirect_to admin_season_path(@season), notice: t("admin.flashes.season_rewards.removed")
    end

    private

    def season_reward_params
      params.require(:season_reward).permit(:level, :reward_type, :reward_key, :name)
    end
  end
end
