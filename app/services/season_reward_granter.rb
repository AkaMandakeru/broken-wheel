# frozen_string_literal: true

# Grants season rewards the participant has earned but not yet received.
# Idempotent via the unique index on season_reward_grants, so concurrent
# recalculations can never double-grant.
class SeasonRewardGranter
  def initialize(participation)
    @participation = participation
    @user = participation.user
    @season = participation.season
  end

  # Battle pass track: every reward at or below the current level, on the
  # tracks this participant is entitled to.
  def grant_for_level(level)
    grant(@season.season_rewards.for_level(level).on_track(@participation.premium?))
  end
  alias grant_up_to grant_for_level

  # Parallel progressions (legacy missions, completion tiers, medal fragments,
  # community milestones) reuse the same idempotent path.
  def grant_for_unlock(kind, value)
    grant(@season.season_rewards.by_unlock(kind.to_s, value).on_track(@participation.premium?))
  end

  private

  def grant(scope)
    scope.find_each do |reward|
      # The unique index is the gate — concurrent recalcs can't double-grant.
      next unless claim(reward)

      apply(reward)
      SeasonActivity.create!(
        season: @season,
        user: @user,
        kind: "reward_unlocked",
        metadata: { reward_type: reward.reward_type, reward_key: reward.reward_key, name: reward.name, track: reward.track }
      )
    end
  end

  def claim(reward)
    return false if @participation.season_reward_grants.exists?(season_reward: reward)

    @participation.season_reward_grants.create!(season_reward: reward, granted_at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false # already granted (concurrent recalc)
  end

  def apply(reward)
    case reward.reward_type
    when "title"    then @user.add_title(reward.reward_key)
    when "theme"    then @user.unlock_theme(reward.reward_key)
    when "badge"    then grant_badge(reward)
    when "coins"    then grant_coins(reward)
    when "cosmetic" then grant_cosmetic(reward)
    when "xp_boost" then grant_xp_boost(reward)
    end
  end

  def grant_badge(reward)
    badge = Badge.find_or_create_by!(name: reward.name.presence || "Season: #{reward.reward_key}") do |b|
      b.badge_type = "season"
      b.icon = "🏅"
      b.description = reward.name
      b.points = 0
    end
    @user.user_badges.find_or_create_by!(badge: badge) { |ub| ub.earned_at = Time.current }
  end

  def grant_coins(reward)
    Wallet.credit(
      @user,
      amount: reward.coins,
      reason: "season_reward",
      reason_key: "season_reward:#{reward.id}",
      metadata: { season_id: @season.id, reward_key: reward.reward_key }
    )
  end

  def grant_cosmetic(reward)
    cosmetic = Cosmetic.find_by(key: reward.reward_key)
    return if cosmetic.nil?

    @user.user_cosmetics.find_or_create_by!(cosmetic: cosmetic) do |uc|
      uc.source = "season_reward"
      uc.unlocked_at = Time.current
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def grant_xp_boost(reward)
    hours = reward.payload["hours"].presence&.to_i || 24
    multiplier = reward.payload["multiplier"].presence&.to_f || 2.0

    @user.user_xp_boosts.find_or_create_by!(source_key: "season_reward:#{reward.id}") do |boost|
      boost.multiplier = multiplier
      boost.starts_at = Time.current
      boost.ends_at = Time.current + hours.hours
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
