# frozen_string_literal: true

class ChallengesController < ApplicationController
  before_action :authenticate_user!, except: [ :index ]
  before_action :set_challenge, only: [ :show, :join, :invite ]

  def index
    @type = params[:type].presence_in(Challenge::CHALLENGE_TYPES)
    @challenges = Challenge.where(status: "active").of_type(@type).order(starts_at: :desc)
    @active_season = Season.active.by_recent.first
    @season_participation = current_user.season_participations.find_by(season: @active_season) if @active_season && user_signed_in?
    @my_participations = participation_index
  end

  def show
    # A challenge can run in several seasons; the page shows one of them, so
    # both the viewer's progress and the ranking must come from the same one or
    # the board would mix scores from different months.
    @season = challenge_season
    @participation = current_user.challenge_participations.for_context(@season).find_by(challenge_id: @challenge.id)
    @participations = @challenge.challenge_participations.for_context(@season).includes(:user).order(progress_value: :desc)
  end

  def join
    if current_user.challenge_participations.for_context(challenge_season).exists?(challenge_id: @challenge.id)
      redirect_to challenge_path(@challenge), alert: t("flashes.challenges.already_joined")
      return
    end

    ChallengeEnroller.call(current_user, @challenge, season: challenge_season)

    Analytics.track(user: current_user, event: "challenge_joined", properties: { challenge_id: @challenge.id, challenge_type: @challenge.challenge_type, sport: @challenge.sport })

    notice = if current_user.connected_to_strava?
      t("flashes.challenges.joined")
    else
      t("flashes.challenges.joined_connect_strava")
    end

    redirect_to challenge_path(@challenge), notice: notice
  end

  def invite
    @participation = current_user.challenge_participations.for_context(challenge_season).find_by(challenge_id: @challenge.id)
    redirect_to challenge_path(@challenge), alert: t("flashes.challenges.must_join_first") unless @participation
  end

  private

  def set_challenge
    @challenge = Challenge.find(params[:id])
  end

  # The active season this challenge belongs to, if any — the context its
  # progress and ranking are read in. Nil means a standalone challenge.
  def challenge_season
    return @challenge_season if defined?(@challenge_season)

    @challenge_season = Season.active
                              .joins(:season_challenges)
                              .where(season_challenges: { challenge_id: @challenge.id })
                              .by_recent
                              .first
  end

  # { challenge_id => participation } for the index, preferring each challenge's
  # season row so the list matches what the challenge page will show.
  def participation_index
    return {} unless user_signed_in?

    current_user.challenge_participations
                .where(challenge_id: @challenges.map(&:id))
                .order(Arel.sql("season_id IS NULL"))
                .index_by(&:challenge_id)
  end
end
