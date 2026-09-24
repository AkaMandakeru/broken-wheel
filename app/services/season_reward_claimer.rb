# frozen_string_literal: true

# What a player can take from their locker, and the taking of it.
#
# A claim is not a new kind of ownership: it ends in the same
# SeasonRewardGranter path every other reward goes through, so the grant ledger,
# the idempotency index and the activity feed all behave identically. The only
# difference is who starts it — the player, not the engine.
#
# Listing and claiming read from ONE method on purpose. They were two queries
# once, and they disagreed: an unrenderable cosmetic was hidden from the locker
# but could still be claimed, handing the player something they could never
# wear. Anything offered is claimable and anything claimable is offered.
class SeasonRewardClaimer
  Result = Struct.new(:status, :reward, keyword_init: true) do
    def claimed? = status == :claimed
  end

  # Every [cosmetic, reward] pair this user may take right now.
  #
  # Seasons are limited to `browsable`: an offer for a season the player cannot
  # open is one they cannot inspect. Cosmetics are limited to `renderable`:
  # claiming something unwearable is a reward in name only.
  def self.offers_for(user, kinds: Cosmetic::PICTURE_KINDS)
    participations = user.season_participations
                         .where(season: Season.browsable)
                         .index_by(&:season_id)
    return [] if participations.empty?

    rewards = SeasonReward.claimable
                          .where(season_id: participations.keys, reward_type: "cosmetic")
                          .includes(:season)
    return [] if rewards.empty?

    owned = user.cosmetics.pluck(:key).to_set
    cosmetics = Cosmetic.of_kind(kinds).renderable
                        .where(key: rewards.map(&:reward_key))
                        .with_artwork.index_by(&:key)

    rewards.filter_map do |reward|
      cosmetic = cosmetics[reward.reward_key]
      next if cosmetic.nil? || owned.include?(reward.reward_key)
      next unless eligible?(reward, participations[reward.season_id])

      [ cosmetic, reward ]
    end
  end

  def self.available_for(user, kind:)
    offers_for(user, kinds: [ kind ])
  end

  def self.eligible?(reward, participation)
    return false if participation.nil?
    return false if reward.premium? && !participation.premium?

    reward.covers_join?(participation.created_at)
  end

  def initialize(user)
    @user = user
  end

  # Claims by cosmetic key. The offer is looked up again rather than trusted
  # from the page the button came from — it may have expired since it rendered.
  def call(key)
    key = key.to_s
    return Result.new(status: :already_owned) if @user.owns_cosmetic?(key)

    _cosmetic, reward = self.class.offers_for(@user).find { |cosmetic, _| cosmetic.key == key }
    return Result.new(status: :unavailable) if reward.nil?

    participation = @user.season_participations.find_by(season_id: reward.season_id)
    SeasonRewardGranter.new(participation).grant_reward(reward)
    Result.new(status: :claimed, reward: reward)
  end
end
