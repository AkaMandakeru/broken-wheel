# frozen_string_literal: true

class ChallengesController < ApplicationController
  before_action :authenticate_user!, except: [ :index ]
  before_action :set_challenge, only: [ :show, :join, :invite ]

  def index
    @challenges = Challenge.where(status: "active").order(starts_at: :desc)
  end

  def show
    @participation = current_user.challenge_participations.find_by(challenge_id: @challenge.id)
    @participations = @challenge.challenge_participations.includes(:user).order(progress_value: :desc)
  end

  def join
    if current_user.challenge_participations.exists?(challenge_id: @challenge.id)
      redirect_to challenge_path(@challenge), alert: t("flashes.challenges.already_joined")
      return
    end

    participation = current_user.challenge_participations.create!(challenge: @challenge)

    if @challenge.challenge_type == "weekly"
      workouts = current_user.workouts.where(workout_date: Challenge.current_week_window)
    elsif @challenge.challenge_type == "monthly"
      start_date = Date.current.beginning_of_month
      end_date = Date.current.end_of_month
      workouts = current_user.workouts.where(workout_date: start_date..end_date)
    else
      workouts = current_user.workouts.none
    end

    workouts = workouts.where(sport: @challenge.sport) if @challenge.sport.present?
    workouts_to_assign = workouts.where(challenge_participation_id: nil)

    if workouts_to_assign.any?
      workouts_to_assign.update_all(challenge_participation_id: participation.id)
      RecomputeChallengeProgress.new(participation).call
    end

    notice = if current_user.connected_to_strava?
                t("flashes.challenges.joined")
              else
                t("flashes.challenges.joined_connect_strava")
              end

    redirect_to challenge_path(@challenge), notice: notice
  end

  def invite
    @participation = current_user.challenge_participations.find_by(challenge_id: @challenge.id)
    redirect_to challenge_path(@challenge), alert: t("flashes.challenges.must_join_first") unless @participation
  end

  private

  def set_challenge
    @challenge = Challenge.find(params[:id])
  end
end
