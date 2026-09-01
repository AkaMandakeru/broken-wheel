# frozen_string_literal: true

# Collects XP waiting on finished challenges.
#
# Answers JSON for the in-page claim animation and HTML for a plain form post,
# so the feature still works if JavaScript doesn't run.
class SeasonClaimsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_season
  before_action :set_participation

  def create
    result = SeasonXpClaimer.new(@participation).call(completion: completion)

    respond_to do |format|
      format.json { render json: claim_json(result) }
      format.html { redirect_to season_path(@season), notice: notice_for(result) }
    end
  end

  private

  # Same reach as the season page itself. Gating only the page would leave this
  # endpoint open, and collecting XP is as much "access" as reading the board.
  def set_season
    @season = Season.browsable.find_by(id: params[:season_id])
    return if @season

    respond_to do |format|
      format.json { head :not_found }
      format.html { redirect_to seasons_path, alert: t("flashes.seasons.archived") }
    end
  end

  def set_participation
    @participation = current_user.season_participations.find_by(season_id: @season.id)
    return if @participation

    respond_to do |format|
      format.json { head :not_found }
      format.html { redirect_to season_path(@season) }
    end
  end

  # Nil claims everything pending.
  def completion
    return nil if params[:id].blank?

    @participation.season_challenge_completions.find_by(id: params[:id])
  end

  def claim_json(result)
    {
      claimed: result.claimed,
      xp_gained: result.xp,
      xp: @participation.xp,
      level: @participation.level,
      levelled_up: result.levelled_up?,
      progress_percent: @participation.progress_percent,
      xp_to_next: @participation.xp_to_next_level,
      remaining: @participation.unclaimed_count
    }
  end

  def notice_for(result)
    return t("seasons.claim.nothing_to_claim") unless result.any?

    t("seasons.claim.claimed", xp: result.xp)
  end
end
