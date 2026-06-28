# frozen_string_literal: true

module Admin
  class SeasonObjectivesController < BaseController
    def create
      @season = Season.find(params[:season_id])
      objective = @season.season_objectives.new(season_objective_params)
      if objective.save
        redirect_to admin_season_path(@season), notice: t("admin.flashes.season_objectives.added")
      else
        redirect_to admin_season_path(@season), alert: objective.errors.full_messages.to_sentence
      end
    end

    def destroy
      @season = Season.find(params[:season_id])
      @season.season_objectives.find_by(id: params[:id])&.destroy
      redirect_to admin_season_path(@season), notice: t("admin.flashes.season_objectives.removed")
    end

    private

    def season_objective_params
      params.require(:season_objective).permit(:kind, :xp_reward, :target, :position, :required, :name)
    end
  end
end
