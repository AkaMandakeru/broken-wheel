# frozen_string_literal: true

module Admin
  class SeasonChallengesController < BaseController
    def create
      @season = Season.find(params[:season_id])
      season_challenge = @season.season_challenges.new(season_challenge_params)
      if season_challenge.save
        redirect_to admin_season_path(@season), notice: t("admin.flashes.season_challenges.added")
      else
        redirect_to admin_season_path(@season), alert: season_challenge.errors.full_messages.to_sentence
      end
    end

    def destroy
      @season = Season.find(params[:season_id])
      @season.season_challenges.find_by(id: params[:id])&.destroy
      redirect_to admin_season_path(@season), notice: t("admin.flashes.season_challenges.removed")
    end

    private

    def season_challenge_params
      params.require(:season_challenge).permit(:challenge_id, :position, :required, :xp_reward)
    end
  end
end
