# frozen_string_literal: true

module Admin
  class ChallengesController < BaseController
    before_action :set_challenge, only: [ :show, :edit, :update, :destroy ]

    def index
      @challenges = Challenge.order(created_at: :desc)
    end

    def show
      @participations = @challenge.challenge_participations.includes(:user).order(progress_value: :desc)
    end

    def new
      @challenge = Challenge.new(status: "active")
    end

    def edit
    end

    def create
      @challenge = Challenge.new(challenge_params)

      if @challenge.save
        redirect_to admin_challenge_path(@challenge), notice: t("admin.flashes.challenges.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @challenge.update(challenge_params)
        redirect_to admin_challenge_path(@challenge), notice: t("admin.flashes.challenges.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @challenge.destroy
      redirect_to admin_challenges_path, notice: t("admin.flashes.challenges.destroyed")
    end

    private

    def set_challenge
      @challenge = Challenge.find(params[:id])
    end

    def challenge_params
      params.require(:challenge).permit(
        :title, :description, :challenge_type, :sport,
        :target_value, :target_unit, :status, :starts_at, :ends_at, :image
      )
    end
  end
end
