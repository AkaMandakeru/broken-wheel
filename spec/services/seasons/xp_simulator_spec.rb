# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seasons::XpSimulator do
  let(:season) { build_season(starts_at: Date.new(2026, 9, 1), ends_at: Date.new(2026, 9, 30)) }

  def daily_row
    described_class.new(season).report.find { |line| line.include?("Daily challenges") }
  end

  def template(key)
    season.daily_challenge_templates.create!(
      key: key, metric: "activity_count", target: 1, sport: "run", xp_reward: 50
    )
  end

  describe "the daily challenge budget" do
    # The draw hands out three distinct templates a day, so it can never offer
    # more than the pool holds. Budgeting the full three against a one-template
    # pool overstated the XP ceiling threefold — enough to make an unreachable
    # top level report as balanced.
    it "budgets one a day when the pool holds one template" do
      template("movimento_do_dia")

      expect(daily_row).to include("1500") # 50 XP × 1 × 30 days
    end

    it "budgets the full three a day once the pool can supply them" do
      %w[a b c d].each { |key| template(key) }

      expect(daily_row).to include("4500") # 50 XP × 3 × 30 days
    end

    it "budgets nothing when there are no templates" do
      expect(daily_row).to include("0")
    end
  end
end
