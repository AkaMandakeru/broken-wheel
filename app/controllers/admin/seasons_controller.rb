# frozen_string_literal: true

module Admin
  class SeasonsController < BaseController
    before_action :set_season, only: [ :show, :edit, :update, :destroy ]

    def index
      @seasons = Season.by_recent
    end

    def show
      @season_challenges = @season.season_challenges.includes(:challenge)
      @season_challenge = SeasonChallenge.new
      @season_reward = SeasonReward.new
      @available_challenges = Challenge.where.not(id: @season.challenges.select(:id)).order(:title)
      @participations = @season.season_participations.by_rank.includes(:user).limit(20)
    end

    def new
      @season = Season.new(status: "upcoming", theme: "default", xp_multiplier: 1.0)
    end

    def edit
    end

    def create
      @season = Season.new(season_params)
      if @season.save
        redirect_to admin_season_path(@season), notice: t("admin.flashes.seasons.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @season.update(season_params)
        redirect_to admin_season_path(@season), notice: t("admin.flashes.seasons.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @season.destroy
      redirect_to admin_seasons_path, notice: t("admin.flashes.seasons.destroyed")
    end

    private

    def set_season
      @season = Season.find(params[:id])
    end

    def season_params
      params.require(:season).permit(:key, :name, :description, :theme, :status, :starts_at, :ends_at, :xp_multiplier, :image)
    end
  end
end
