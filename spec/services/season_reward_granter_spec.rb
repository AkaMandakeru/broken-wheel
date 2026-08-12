# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeasonRewardGranter do
  let(:user) { build_user }
  let(:season) { build_season }
  let(:participation) { SeasonProgressService.ensure_participation(user, season) }

  def reward(level:, track: "free", type: "badge", key: "reward-#{SecureRandom.hex(3)}", **extra)
    season.season_rewards.create!(
      { level: level, track: track, reward_type: type, reward_key: key, name: key.humanize }.merge(extra)
    )
  end

  describe "battle pass track" do
    it "grants every free reward at or below the level" do
      reward(level: 1)
      reward(level: 3)
      reward(level: 10)

      described_class.new(participation).grant_for_level(5)

      expect(participation.season_reward_grants.count).to eq(2)
    end

    # The premium track is the whole point of the paid pass; leaking it to free
    # participants would give the purchase away.
    it "withholds premium rewards from a free participant" do
      reward(level: 2, track: "free")
      reward(level: 2, track: "premium")

      described_class.new(participation).grant_for_level(5)

      granted = participation.season_reward_grants.includes(:season_reward).map { |g| g.season_reward.track }
      expect(granted).to eq([ "free" ])
    end

    it "grants both tracks to a premium participant" do
      reward(level: 2, track: "free")
      reward(level: 2, track: "premium")
      participation.update!(premium: true)

      described_class.new(participation).grant_for_level(5)

      expect(participation.season_reward_grants.count).to eq(2)
    end

    it "back-grants premium rewards when the pass is upgraded mid-season" do
      reward(level: 2, track: "premium")
      participation.update!(level: 6)
      described_class.new(participation).grant_for_level(6)
      expect(participation.season_reward_grants.count).to eq(0)

      participation.grant_premium!

      expect(participation.season_reward_grants.count).to eq(1)
    end
  end

  describe "idempotency" do
    it "does not re-grant on repeated runs" do
      reward(level: 1)
      granter = described_class.new(participation)

      3.times { granter.grant_for_level(5) }

      expect(participation.season_reward_grants.count).to eq(1)
    end
  end

  describe "parallel unlock kinds" do
    it "grants legacy rewards by completed mission count" do
      reward(level: nil, key: "golden_footsteps", unlock_kind: "legacy", unlock_value: 5)

      described_class.new(participation).grant_for_unlock("legacy", 4)
      expect(participation.season_reward_grants.count).to eq(0)

      described_class.new(participation).grant_for_unlock("legacy", 5)
      expect(participation.season_reward_grants.count).to eq(1)
    end

    it "grants completion tiers by percentage" do
      reward(level: nil, key: "bronze", unlock_kind: "completion_tier", unlock_value: 25)
      reward(level: nil, key: "silver", unlock_kind: "completion_tier", unlock_value: 50)

      described_class.new(participation).grant_for_unlock("completion_tier", 50)

      expect(participation.season_reward_grants.count).to eq(2)
    end
  end

  describe "reward payloads" do
    it "credits coins through the ledger exactly once" do
      reward(level: 1, type: "coins", key: "coins_500", coins: 500)
      granter = described_class.new(participation)

      2.times { granter.grant_for_level(1) }

      expect(user.reload.coins).to eq(500)
      expect(user.coin_transactions.count).to eq(1)
    end

    it "unlocks a cosmetic the user owns afterwards" do
      Cosmetic.create!(key: "silver_frame", kind: "frame", name: "Silver Frame")
      reward(level: 1, type: "cosmetic", key: "silver_frame")

      described_class.new(participation).grant_for_level(1)

      expect(user.reload.owns_cosmetic?("silver_frame")).to be(true)
    end

    it "starts a bounded XP boost" do
      reward(level: 1, type: "xp_boost", key: "boost_1d", payload: { "hours" => 24, "multiplier" => 2.0 })

      described_class.new(participation).grant_for_level(1)

      boost = user.reload.user_xp_boosts.first
      expect(boost.multiplier.to_f).to eq(2.0)
      expect(boost.covers?(Time.current)).to be(true)
      expect(boost.covers?(3.days.from_now)).to be(false)
    end
  end
end
