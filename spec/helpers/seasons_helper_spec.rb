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

  describe "#season_challenge_date_range" do
    let(:season) { build_season } # 2026-08-01 .. 2026-08-31

    def challenge_over(starts_at, ends_at)
      challenge = build_challenge(key: "c_#{SecureRandom.hex(3)}", requirements: [ { metric: "activity_count", target: 1 } ])
      season.season_challenges.create!(challenge: challenge, category: "special", xp_reward: 10,
                                       starts_at: starts_at, ends_at: ends_at)
    end

    # "12/10 – 12/10" is a range of one. A one-day special reads as a date.
    it "renders a single day as one date" do
      expect(helper.season_challenge_date_range(challenge_over("2026-08-12", "2026-08-12"))).to eq("12/08")
    end

    it "renders a longer window as a range" do
      expect(helper.season_challenge_date_range(challenge_over("2026-08-03", "2026-08-09"))).to eq("03/08 – 09/08")
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
