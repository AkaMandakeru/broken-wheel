# frozen_string_literal: true

# Grants every season reward up to the given level that the participant hasn't
# received yet. Idempotent via season_reward_grants.
class SeasonRewardGranter
  def initialize(participation)
    @participation = participation
    @user = participation.user
    @season = participation.season
  end

  def grant_up_to(level)
    @season.season_rewards.where(level: ..level).find_each do |reward|
      next if @participation.season_reward_grants.exists?(season_reward: reward)

      apply(reward)
      @participation.season_reward_grants.create!(season_reward: reward, granted_at: Time.current)
      SeasonActivity.create!(
        season: @season,
        user: @user,
        kind: "reward_unlocked",
        metadata: { reward_type: reward.reward_type, reward_key: reward.reward_key, name: reward.name }
      )
    end
  end

  private

  def apply(reward)
    case reward.reward_type
    when "title" then @user.add_title(reward.reward_key)
    when "theme" then @user.unlock_theme(reward.reward_key)
    when "badge" then grant_badge(reward)
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
end
