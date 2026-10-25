class SeasonActivity < ApplicationRecord
  belongs_to :season
  # Community milestones belong to the season as a whole, so they carry no user.
  belongs_to :user, optional: true

  KINDS = %w[
    challenge_completed objective_completed level_up reward_unlocked
    daily_completed special_completed legacy_mission_completed
    community_milestone community_tier_cleared season_finalized season_started
  ].freeze

  validates :kind, inclusion: { in: KINDS }

  scope :recent, -> { order(created_at: :desc) }
  scope :community, -> { where(user_id: nil) }

  def community?
    user_id.nil?
  end

  # The feed line after the player's name ("completed X (+50 XP)"), in the
  # current locale. Shared by the season page and the mobile API.
  def description
    meta = metadata || {}
    goal = meta["title"].presence || meta["goal"]

    case kind
    when "challenge_completed"
      I18n.t("seasons.activity.challenge_completed", challenge: meta["challenge"], xp: meta["xp"])
    when "objective_completed"
      I18n.t("seasons.activity.objective_completed", objective: meta["objective"], xp: meta["xp"])
    when "level_up"
      I18n.t("seasons.activity.level_up", level: meta["level"])
    when "reward_unlocked"
      I18n.t("seasons.activity.reward_unlocked", name: meta["name"].presence || meta["reward_key"])
    when "daily_completed"
      I18n.t("seasons.activity.daily_completed", daily: meta["daily"], xp: meta["xp"])
    when "special_completed"
      I18n.t("seasons.activity.special_completed", challenge: meta["challenge"], xp: meta["xp"])
    when "legacy_mission_completed"
      I18n.t("seasons.activity.legacy_mission_completed", objective: meta["objective"], xp: meta["xp"])
    when "community_milestone"
      I18n.t("seasons.activity.community_milestone", percent: meta["percent"], goal: goal)
    when "community_tier_cleared"
      I18n.t("seasons.activity.community_tier_cleared",
             goal: goal, tier: meta["tier"], next_tier: meta["next_tier"],
             next_target: ActiveSupport::NumberHelper.number_to_delimited(meta["next_target"].to_f.round))
    when "season_finalized"
      I18n.t("seasons.activity.season_finalized", level: meta["level"], percent: meta["completion_percent"])
    else
      kind
    end
  end
end
