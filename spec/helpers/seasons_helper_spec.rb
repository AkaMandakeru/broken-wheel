# frozen_string_literal: true

require "rails_helper"

# Spec types are not inferred from location in this suite (see rails_helper).
RSpec.describe SeasonsHelper, type: :helper do
  describe "#special_challenge_chip" do
    let(:season) { build_season }

    def challenge_in(category)
      challenge = build_challenge(key: "c_#{category}", requirements: [ { metric: "activity_count", target: 1 } ])
      season.season_challenges.create!(challenge: challenge, category: category, xp_reward: 10)
    end

    it "badges a special challenge" do
      chip = helper.special_challenge_chip(challenge_in("special"))

      expect(chip).to include(I18n.t("seasons.show.special"))
    end

    it "renders nothing for an ordinary challenge" do
      expect(helper.special_challenge_chip(challenge_in("monthly"))).to be_nil
    end

    it "renders nothing when there is no challenge at all" do
      expect(helper.special_challenge_chip(nil)).to be_nil
    end
  end

  describe "#season_category_icon" do
    it "gives special challenges their own icon" do
      expect(helper.season_category_icon("special")).to include("fa-star")
    end

    it "falls back for an unknown category" do
      expect(helper.season_category_icon("nonsense")).to include("fa-flag-checkered")
    end
  end
end
