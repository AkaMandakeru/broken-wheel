# frozen_string_literal: true

module Admin
  # Test data for a season: put a player at any level, with any mix of
  # challenges, dailies and rewards, before the season has even started.
  #
  # Answers 404 wherever the sandbox is off — see SeasonSandbox.enabled?.
  class SeasonSandboxesController < BaseController
    before_action :require_sandbox!
    before_action :set_season
    before_action :set_user, except: [ :show, :community, :add_bots, :remove_bots ]

    rescue_from SeasonSandbox::Error do |error|
      redirect_back_to_sandbox alert: error.message
    end

    def show
      @user = if params[:user_id].present?
        User.find_by(id: params[:user_id])
      elsif params[:email].present?
        User.find_by(email: params[:email].strip.downcase)
      end
      flash.now[:alert] = t("admin.season_sandbox.user_not_found") if params[:email].present? && @user.nil?
      @users = User.where.not(id: SeasonSandbox.bots.select(:id)).order(:email).limit(500)
      @bots_count = SeasonSandbox.bots.count
      return unless @user

      @sandbox = SeasonSandbox.new(@season, @user)
      @participation = @sandbox.participation
      @completed_challenge_ids = @participation&.season_challenge_completions&.pluck(:season_challenge_id).to_a
      @claimed_challenge_ids = @participation&.season_challenge_completions&.claimed&.pluck(:season_challenge_id).to_a
      @completed_objective_ids = @participation&.season_objective_completions&.pluck(:season_objective_id).to_a
      @granted_reward_ids = @participation&.granted_reward_ids.to_a
      @sandbox_workouts_count = @user.workouts.where(provider: SeasonSandbox::WORKOUT_PROVIDER).count
    end

    def enroll
      sandbox.enroll!
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.enrolled")
    end

    def workouts
      count = sandbox.generate_workouts!(
        count: params[:count], sport: params[:sport], min_km: params[:min_km], max_km: params[:max_km],
        from: params[:from], to: params[:to]
      )
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.workouts", count: count)
    end

    def challenges
      count = sandbox.complete_challenges!(ids: selected_ids, claim: params[:claim] == "1")
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.challenges", count: count)
    end

    def objectives
      count = sandbox.complete_objectives!(ids: selected_ids)
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.objectives", count: count)
    end

    def dailies
      count = sandbox.complete_dailies!(days: params[:days])
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.dailies", count: count)
    end

    def level
      sandbox.set_level!(params[:level])
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.level", level: sandbox.participation.level)
    end

    def xp
      sandbox.add_xp!(params[:amount])
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.xp", xp: sandbox.participation.xp)
    end

    def premium
      sandbox.set_premium!(params[:premium] == "1")
      key = sandbox.participation.premium? ? "premium_on" : "premium_off"
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.#{key}")
    end

    def reward
      reward = @season.season_rewards.find(params[:reward_id])
      sandbox.grant_reward!(reward)
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.reward", name: reward.name.presence || reward.reward_key)
    end

    def recalculate
      sandbox.recalculate!
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.recalculated")
    end

    def reset
      sandbox.reset!
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.reset", name: @user.email)
    end

    def community
      SeasonSandbox.run_community!(@season)
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.community")
    end

    def add_bots
      bots = SeasonSandbox.add_bots!(@season, count: params[:count])
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.bots_added", count: bots.size)
    end

    def remove_bots
      count = SeasonSandbox.remove_bots!
      redirect_back_to_sandbox notice: t("admin.season_sandbox.flashes.bots_removed", count: count)
    end

    private

    # A 404 rather than a redirect: where the sandbox is off it should look like
    # it does not exist.
    def require_sandbox!
      raise ActionController::RoutingError, "Not Found" unless SeasonSandbox.enabled?
    end

    def set_season
      @season = Season.find(params[:season_id])
    end

    def set_user
      @user = User.find(params[:user_id])
    end

    def sandbox
      @sandbox ||= SeasonSandbox.new(@season, @user)
    end

    def selected_ids
      Array(params[:ids]).compact_blank.map(&:to_i).presence
    end

    def redirect_back_to_sandbox(**flash)
      redirect_to admin_season_sandbox_path(@season, user_id: @user&.id || params[:user_id].presence), **flash
    end
  end
end
