# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeasonChallenge, type: :model do
  # Special challenges were called "hidden" while they stayed off the board
  # until a player completed one. Blueprints exported before the rename still
  # say so, and they have to keep importing.
  describe ".canonical_category" do
    it "passes a current category through untouched" do
      described_class::CATEGORIES.each do |category|
        expect(described_class.canonical_category(category)).to eq(category)
      end
    end

    it "maps the legacy spelling to the one in use" do
      expect(described_class.canonical_category("hidden")).to eq("special")
    end

    it "accepts a symbol" do
      expect(described_class.canonical_category(:hidden)).to eq("special")
    end

    it "leaves an unknown value alone rather than guessing" do
      expect(described_class.canonical_category("nonsense")).to eq("nonsense")
    end
  end

  describe ".known_category?" do
    it "accepts every current category" do
      expect(described_class::CATEGORIES).to all(satisfy { |c| described_class.known_category?(c) })
    end

    it "accepts the legacy spelling" do
      expect(described_class.known_category?("hidden")).to be(true)
    end

    it "rejects anything else" do
      expect(described_class.known_category?("nonsense")).to be(false)
      expect(described_class.known_category?(nil)).to be(false)
    end
  end

  describe "#special?" do
    let(:season) { build_season }

    def challenge_in(category)
      challenge = build_challenge(key: "c_#{category}", requirements: [ { metric: "activity_count", target: 1 } ])
      season.season_challenges.create!(challenge: challenge, category: category, xp_reward: 10)
    end

    it "is true only for the special category" do
      expect(challenge_in("special")).to be_special
      expect(challenge_in("monthly")).not_to be_special
    end

    it "backs the .special scope" do
      special = challenge_in("special")
      challenge_in("elite")

      expect(season.season_challenges.special).to contain_exactly(special)
    end
  end

  # The column that used to drive the hiding is gone; the category is the marker.
  it "no longer carries a hidden flag" do
    expect(described_class.column_names).not_to include("hidden")
  end
end
