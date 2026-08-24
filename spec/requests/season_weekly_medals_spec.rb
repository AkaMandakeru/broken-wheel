# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Weekly challenge dates and medals", type: :request do
  include SeasonsHelper

  let(:user) { build_user }
  let(:season) { build_season }
  let!(:participation) { SeasonProgressService.ensure_participation(user, season) }

  # Easiest → hardest, which is what the bronze/silver/gold ladder encodes.
  let(:challenge) do
    build_challenge(
      key: "week_one", sport: "run",
      requirements: [
        { metric: "distance_km", target: 10 },
        { metric: "activity_count", target: 4 },
        { metric: "longest_activity_km", target: 8 }
      ]
    )
  end

  def attach_week(starts_at:, ends_at:)
    season.season_challenges.create!(
      challenge: challenge, category: "weekly", week_index: 1,
      xp_reward: 1000, starts_at: starts_at, ends_at: ends_at
    )
  end

  def run_and_recompute(count:, km:, from: Date.new(2026, 8, 1))
    count.times { |i| build_workout(user, date: from + i, km: km) }
    ChallengeEnroller.call(user, challenge, season: season)
    RecomputeChallengeProgress.new(user.challenge_participations.find_by(challenge: challenge, season: season)).call
  end

  describe "the date range" do
    it "shows the week's own dates above the title" do
      attach_week(starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7))
      sign_in user

      get season_path(season)

      expect(response.body).to include("01/08 – 07/08")
    end

    it "formats from the season challenge, not the challenge" do
      sc = attach_week(starts_at: Date.new(2026, 8, 15), ends_at: Date.new(2026, 8, 21))

      expect(season_challenge_date_range(sc)).to eq("15/08 – 21/08")
    end

    # A monthly challenge has no week to show.
    it "is left off non-weekly challenges" do
      other = build_challenge(key: "monthly_one", requirements: [ { metric: "distance_km", target: 5 } ])
      season.season_challenges.create!(challenge: other, category: "monthly", xp_reward: 100)
      sign_in user

      get season_path(season)

      expect(response.body).not_to include("01/08 – 31/08")
    end
  end

  describe "the medal ladder" do
    it "assigns bronze, silver then gold to the three requirements" do
      expect(requirement_medal(0)).to eq("bronze")
      expect(requirement_medal(1)).to eq("silver")
      expect(requirement_medal(2)).to eq("gold")
    end

    # A fourth requirement would have no distinct tier to represent.
    it "stops after gold" do
      expect(requirement_medal(3)).to be_nil
    end

    it "renders a medal per requirement row" do
      attach_week(starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7))
      run_and_recompute(count: 2, km: 6)
      sign_in user

      get season_path(season)

      expect(response.body.scan("fa-medal").size).to be >= 3
    end
  end

  describe "the medal earned" do
    def medal_for(count:, km:)
      run_and_recompute(count: count, km: km)
      highest_medal_earned(user.challenge_participations.find_by(challenge: challenge, season: season))
    end

    it "is nil when nothing is met" do
      attach_week(starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7))

      expect(medal_for(count: 1, km: 2)).to be_nil
    end

    it "is bronze on the first requirement alone" do
      attach_week(starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7))

      expect(medal_for(count: 2, km: 6)).to eq("bronze")
    end

    it "is silver on the first two" do
      attach_week(starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7))

      expect(medal_for(count: 4, km: 3)).to eq("silver")
    end

    it "is gold when all three are met" do
      attach_week(starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7))

      expect(medal_for(count: 4, km: 9)).to eq("gold")
    end
  end

  describe "showing the result after the week ends" do
    before { travel_to Time.utc(2026, 8, 25, 12) }
    after { travel_back }

    it "shows the earned medal beside the label once the week is over" do
      attach_week(starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7))
      run_and_recompute(count: 2, km: 6)
      sign_in user

      get season_path(season)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.medals.bronze")))
    end

    it "treats a week still in progress as unfinished" do
      sc = attach_week(starts_at: Date.new(2026, 8, 22), ends_at: Date.new(2026, 8, 31))

      expect(sc.window_ended?).to be(false)
    end

    it "treats a closed week as finished" do
      sc = attach_week(starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7))

      expect(sc.window_ended?).to be(true)
    end
  end
end
