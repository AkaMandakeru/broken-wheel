# frozen_string_literal: true

class ChallengesController < ApplicationController
  before_action :authenticate_user!, except: [:index]
  before_action :set_challenge, only: [:show, :join, :invite]

  def index
    @challenges = Challenge.where(status: "active").order(starts_at: :desc)
  end

  def show
    @participation = current_user.challenge_participations.find_by(challenge_id: @challenge.id)
    @participations = @challenge.challenge_participations.includes(:user).order(progress_value: :desc)
  end

  def join
    if current_user.challenge_participations.exists?(challenge_id: @challenge.id)
      redirect_to challenge_path(@challenge), alert: "You already joined this challenge."
      return
    end

    participation = current_user.challenge_participations.create!(challenge: @challenge)
    redirect_to challenge_path(@challenge), notice: "Joined challenge!"
  end

  def invite
    @participation = current_user.challenge_participations.find_by(challenge_id: @challenge.id)
    redirect_to challenge_path(@challenge), alert: "Join the challenge first to invite friends." unless @participation
  end

  private

  def set_challenge
    @challenge = Challenge.find(params[:id])
  end
end
