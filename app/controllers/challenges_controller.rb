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
      redirect_to challenge_path(@challenge), alert: "You already joined this challenge."
      return
    end

    participation = current_user.challenge_participations.create!(challenge: @challenge)

    if @challenge.challenge_type == "weekly"
      start_date = Date.current.beginning_of_week(:monday)
      end_date = Date.current.end_of_week(:monday)
      workouts = current_user.workouts.where(workout_date: start_date..end_date)
    elsif @challenge.challenge_type == "monthly"
      start_date = Date.current.beginning_of_month
      end_date = start_date + 29.days
      workouts = current_user.workouts.where(workout_date: start_date..end_date)
    else
      workouts = current_user.workouts.none
    end

    workouts = workouts.where(sport: @challenge.sport) if @challenge.sport.present?
    workouts_to_assign = workouts.where(challenge_participation_id: nil)

    if workouts_to_assign.any?
      workouts_to_assign.update_all(challenge_participation_id: participation.id)

      progress = @challenge.target_unit == "km" ? participation.workouts.sum(:distance_km) : (participation.workouts.sum(:duration_minutes).to_f / 60)
      participation.update(progress_value: progress)

      if progress >= @challenge.target_value.to_f
        participation.update(completed_at: Time.current)
        badge = Badge.find_or_create_by!(name: "Completed: #{@challenge.title}") do |b|
          b.icon = "🏆"
          b.description = "Completed #{@challenge.title}"
          b.badge_type = "challenge_completion"
        end
        unless current_user.user_badges.exists?(badge: badge, challenge: @challenge)
          current_user.user_badges.create!(badge: badge, challenge: @challenge, earned_at: Time.current)
        end
      end
    end

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
