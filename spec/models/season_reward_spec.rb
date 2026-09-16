# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeasonReward, type: :model do
  describe ".cosmetic_unlocks_for" do
    let(:banner) { build_cosmetic(key: "legacy_of_champions", kind: "banner") }

    def cosmetic_reward(season, key, level:)
      season.season_rewards.create!(
        reward_type: "cosmetic", reward_key: key, name: key.humanize,
        unlock_kind: "level", level: level, track: "free"
      )
    end

    it "is empty when asked about nothing" do
      expect(described_class.cosmetic_unlocks_for([])).to eq({})
      expect(described_class.cosmetic_unlocks_for(nil)).to eq({})
    end

    it "maps a cosmetic key to the reward that offers it" do
      season = build_season(name: "Season Nine")
      reward = cosmetic_reward(season, banner.key, level: 12)

      expect(described_class.cosmetic_unlocks_for([ banner.key ])).to eq(banner.key => reward)
    end

    # A cosmetic can be offered by more than one season. The locker shows where
    # a player can get it first, not wherever it happens to appear last.
    it "picks the earliest unlock when several seasons offer the same cosmetic" do
      early = cosmetic_reward(build_season(name: "Season Eight"), banner.key, level: 4)
      cosmetic_reward(build_season(name: "Season Nine"), banner.key, level: 27)

      expect(described_class.cosmetic_unlocks_for([ banner.key ])[banner.key]).to eq(early)
    end

    it "ignores rewards that are not cosmetics" do
      season = build_season
      season.season_rewards.create!(
        reward_type: "title", reward_key: banner.key, name: "A title",
        unlock_kind: "level", level: 2, track: "free"
      )

      expect(described_class.cosmetic_unlocks_for([ banner.key ])).to eq({})
    end

    it "says nothing about a cosmetic no season hands out" do
      expect(described_class.cosmetic_unlocks_for([ "never_offered" ])).to eq({})
    end
  end
end
