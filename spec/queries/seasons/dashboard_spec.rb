# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seasons::Dashboard do
  before { travel_to Time.utc(2026, 8, 15, 12) }
  after { travel_back }

  let(:user) { build_user }
  let(:season) { build_season }

  describe "#enroll!" do
    it "joins an active season" do
      participation = described_class.new(season, user: user).enroll!

      expect(participation).to be_persisted
      expect(participation.user).to eq(user)
    end

    it "leaves a season that hasn't started alone" do
      season.update_columns(status: "upcoming")

      expect(described_class.new(season, user: user).enroll!).to be_nil
      expect(user.season_participations).to be_empty
    end

    it "does nothing for a guest" do
      expect(described_class.new(season).enroll!).to be_nil
    end
  end

  it "reads the participation without creating one" do
    expect(described_class.new(season, user: user).participation).to be_nil
    expect(user.season_participations).to be_empty
  end

  it "queries each section once" do
    dashboard = described_class.new(season, user: user)

    expect(dashboard.challenges).to equal(dashboard.challenges)
    expect(dashboard.leaderboard).to equal(dashboard.leaderboard)
  end

  it "orders weeklies by week number" do
    [ 2, 1 ].each do |week|
      challenge = build_challenge(key: "week_#{week}", requirements: [ { metric: "activity_count", target: 1 } ])
      season.season_challenges.create!(challenge: challenge, category: "weekly", week_index: week)
    end

    expect(described_class.new(season).weekly_challenges.map(&:week_index)).to eq([ 1, 2 ])
  end

  it "keeps aged-out seasons to admins" do
    build_season(status: "ended", starts_at: Date.new(2026, 7, 1), ends_at: Date.new(2026, 7, 31))
    old = build_season(status: "ended", starts_at: Date.new(2026, 6, 1), ends_at: Date.new(2026, 6, 30))

    expect(described_class.season_scope(user)).not_to include(old)
    expect(described_class.season_scope(nil)).not_to include(old)
    expect(described_class.season_scope(build_user(admin: true))).to include(old)
  end
end
