# frozen_string_literal: true

class SeasonsController < ApplicationController
  before_action :authenticate_user!, except: [ :index, :show ]
  before_action :set_season, only: [ :show ]

  def index
    @active_seasons = Season.active.by_recent
    @past_seasons = Season.recent_archive
  end

  def show
    # Lazy auto-enrollment: viewing an active season creates the participation
    # so progress/rank show immediately (starting at zero).
    @participation = if user_signed_in? && @season.active?
      SeasonProgressService.ensure_participation(current_user, @season)
    elsif user_signed_in?
      current_user.season_participations.find_by(season_id: @season.id)
    end

    @unclaimed_completions = @participation&.unclaimed_completions.to_a

    load_challenges
    load_objectives
    load_dailies
    load_rewards
    load_leaderboard
    load_community

    @activities = @season.season_activities.recent.includes(:user).limit(15)

    track_announcement_click
  end

  private

  # The banner's CTA carries ?from=announcement, so the click is measurable
  # without a redirect hop or a second endpoint. Deliberately no "shown" event:
  # the banner renders on every page, and that would drown the funnel.
  def track_announcement_click
    return unless user_signed_in? && params[:from] == "announcement"

    SeasonAnalytics.track(user: current_user, event: "season_announcement_clicked", season: @season)
  end

  # A season that has aged out is closed, not missing — so this sends the player
  # back to the list with a reason rather than a bare 404.
  def set_season
    @season = season_scope.find_by(id: params[:id])
    return if @season

    redirect_to seasons_path, alert: t("flashes.seasons.archived")
  end

  # Admins keep the whole history, so the admin panel's "view public" link still
  # resolves for a season players can no longer open.
  def season_scope
    current_user&.admin? ? Season.all : Season.browsable
  end

  def load_challenges
    scope = @season.season_challenges.includes(challenge: :challenge_requirements)

    # Secrets stay off the board until the player finds them.
    @discovered_secret_ids = @participation&.season_challenge_completions&.pluck(:season_challenge_id) || []
    visible = scope.reject { |sc| sc.hidden? && !@discovered_secret_ids.include?(sc.id) }

    @challenges_by_category = visible.group_by(&:category)
    @weekly_challenges = (@challenges_by_category["weekly"] || []).sort_by { |sc| sc.week_index.to_i }
    @season_challenges = visible
    @my_challenge_progress = my_challenge_progress(visible.map(&:challenge_id))
  end

  def load_objectives
    @season_objectives = @season.season_objectives.standard
    @legacy_missions = @season.season_objectives.legacy
    @completed_objective_ids = @participation&.season_objective_completions&.pluck(:season_objective_id) || []
    @legacy_completed_count = @legacy_missions.count { |m| @completed_objective_ids.include?(m.id) }
  end

  def load_dailies
    return @daily_assignments = [] unless @participation && @season.active?

    # Assigning here as well as in the nightly job means someone who joins
    # mid-day sees today's set immediately. The draw is deterministic, so both
    # paths produce the same three.
    @daily_assignments = DailyChallenges::Assigner.call(current_user, @season)
    @daily_progress = daily_progress(@daily_assignments)
  end

  def load_rewards
    @rewards = @season.season_rewards.where(unlock_kind: "level").order(:level, :track)
    @rewards_by_level = @rewards.group_by(&:level)
    @bonus_rewards = @season.season_rewards.where.not(unlock_kind: "level").order(:unlock_kind, :unlock_value)
    @granted_reward_ids = @participation&.granted_reward_ids || []
  end

  def load_leaderboard
    @board = (params[:board].presence || "xp").to_sym
    @leaderboard = SeasonLeaderboard.new(@season, board: @board)
    @leaderboard_rows = @leaderboard.top(10)
    @my_position = @leaderboard.position_for(@participation)
  end

  def load_community
    @community_goal = @season.season_community_goals.includes(:season_community_milestones).first
  end

  # { challenge_id => participation } for the current user, for the season's challenges.
  def my_challenge_progress(challenge_ids)
    return {} unless user_signed_in?

    current_user.challenge_participations
                .where(challenge_id: challenge_ids, season_id: @season.id)
                .index_by(&:challenge_id)
  end

  # Live value for each of today's dailies, so the bars move before the next
  # recalculation lands. One context is built and shared, so the whole set costs
  # a single read of the user's workouts.
  def daily_progress(assignments)
    return {} if assignments.empty?

    context = ChallengeMetrics::Context.new(
      user: current_user, window: nil, season: @season, participation: @participation
    )

    assignments.index_with { |assignment| assignment.progress_in(context) }
  end
end
