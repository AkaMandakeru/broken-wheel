# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Season level configuration" do
  describe Seasons::LevelCurve do
    it "spreads the requested number of levels across the XP range" do
      curve = described_class.build(10, top_xp: 17_110)

      expect(curve.size).to eq(10)
      expect(curve.first).to eq(0)
      expect(curve.last).to eq(17_110)
      expect(curve).to eq(curve.sort)
    end

    it "builds any level count the season asks for" do
      [ 1, 2, 3, 5, 10, 30, 100 ].each do |levels|
        curve = described_class.build(levels, top_xp: 10_000)
        expect(curve.size).to eq(levels), "expected #{levels} thresholds"
        expect(described_class.new(curve).max_level).to eq(levels)
      end
    end

    it "collapses to a single level when asked for one" do
      expect(described_class.build(1)).to eq([ 0 ])
    end

    # The whole point of separating the two numbers: fewer levels should mean
    # levelling up less often, not a season that is easier to max.
    it "keeps the top level equally expensive regardless of level count" do
      short = described_class.new(described_class.build(5, top_xp: 17_110))
      long  = described_class.new(described_class.build(30, top_xp: 17_110))

      expect(short.floor_for(short.max_level)).to eq(long.floor_for(long.max_level))
      expect(short.level_for(17_110)).to eq(5)
      expect(long.level_for(17_110)).to eq(30)
    end

    it "front-loads early levels so a newcomer moves quickly" do
      curve = described_class.new(described_class.build(10, top_xp: 10_000, exponent: 1.5))
      first_gap = curve.floor_for(2) - curve.floor_for(1)
      last_gap  = curve.floor_for(10) - curve.floor_for(9)

      expect(first_gap).to be < last_gap
    end
  end

  describe Season do
    it "derives the curve from the level count on create" do
      season = build_season(max_level: 8, top_level_xp: 4_000, level_curve: [])

      expect(season.level_curve.size).to eq(8)
      expect(season.level_curve.last).to eq(4_000)
      expect(season.level_curve_object.max_level).to eq(8)
    end

    # Before this, the stored curve's length defined the level count, so editing
    # max_level in the admin form silently did nothing.
    it "rebuilds the curve when the level count changes" do
      season = build_season(max_level: 30)
      expect(season.level_curve.size).to eq(30)

      season.update!(max_level: 6)

      expect(season.reload.level_curve.size).to eq(6)
      expect(season.level_curve_object.max_level).to eq(6)
    end

    it "rebuilds the curve when the top-level XP changes" do
      season = build_season(max_level: 10, top_level_xp: 5_000)
      season.update!(top_level_xp: 20_000)

      expect(season.reload.level_curve.last).to eq(20_000)
    end

    it "accepts a level count of 10 or fewer" do
      expect(build_season(max_level: 10)).to be_valid
      expect(build_season(max_level: 3)).to be_valid
      expect(build_season(max_level: 1)).to be_valid
    end

    it "rejects a level count outside the supported range" do
      expect(Season.new(name: "x", max_level: 0)).not_to be_valid
      expect(Season.new(name: "x", max_level: Season::MAX_SUPPORTED_LEVEL + 1)).not_to be_valid
    end

    it "recomputes a participant's level against the new curve" do
      season = build_season(max_level: 30, top_level_xp: 17_110)
      user = build_user
      participation = SeasonProgressService.ensure_participation(user, season)
      participation.update!(xp: 9_000)

      expect(season.level_curve_object.level_for(9_000)).to be > 15

      season.update!(max_level: 5)
      SeasonProgressService.new(participation.reload).recalculate

      expect(season.reload.level_curve_object.level_for(9_000)).to be <= 5
    end

    describe "unreachable content" do
      let(:season) { build_season(max_level: 10) }

      it "flags rewards pinned above the level ceiling" do
        season.season_rewards.create!(level: 4, reward_type: "badge", reward_key: "ok")
        season.season_rewards.create!(level: 25, reward_type: "badge", reward_key: "stranded")

        season.update!(max_level: 10)

        expect(season.unreachable_rewards.pluck(:reward_key)).to eq([ "stranded" ])
        expect(season.level_config_warnings.map { |w| w[:kind] }).to include(:rewards)
      end

      it "flags challenges gated above the level ceiling" do
        challenge = build_challenge(key: "gated", requirements: [ { metric: "distance_km", target: 5 } ])
        season.season_challenges.create!(challenge: challenge, category: "elite", unlock_level: 20)

        expect(season.unreachable_challenges.count).to eq(1)
      end

      it "reports nothing when everything fits" do
        season.season_rewards.create!(level: 9, reward_type: "badge", reward_key: "fine")

        expect(season.level_config_warnings).to be_empty
      end
    end
  end
end
