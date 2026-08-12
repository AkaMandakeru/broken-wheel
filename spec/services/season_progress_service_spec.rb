# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeasonProgressService do
  let(:user) { build_user }
  let(:season) { build_season }
  let(:participation) { described_class.ensure_participation(user, season) }

  def recalculate
    described_class.new(participation).recalculate
    participation.reload
  end

  describe "XP breakdown" do
    it "totals every source and reports them separately" do
      3.times { |i| build_workout(user, date: Date.new(2026, 8, 3 + i), km: 5) }

      recalculate

      breakdown = participation.xp_breakdown
      expect(breakdown["workouts"]).to eq(3 * described_class::WORKOUT_XP)
      expect(breakdown["consistency"]).to eq(described_class::CONSISTENCY_XP_PER_WEEK)
      expect(participation.xp).to eq(breakdown.except("multiplier").values.sum)
    end

    it "applies the season multiplier to the total" do
      season.update!(xp_multiplier: 2.0)
      build_workout(user, date: Date.new(2026, 8, 3))

      recalculate

      expect(participation.xp).to eq(participation.xp_breakdown.except("multiplier").values.sum * 2)
    end

    it "ignores workouts outside the season window" do
      build_workout(user, date: Date.new(2026, 7, 15))

      recalculate

      expect(participation.xp_breakdown["workouts"]).to eq(0)
    end
  end

  describe "XP boosts" do
    # Season XP is recomputed from scratch, so a boost applied to the total would
    # keep paying after it expired and would retroactively inflate the whole month.
    it "multiplies only the workouts logged while the boost was live" do
      user.user_xp_boosts.create!(
        multiplier: 2.0, source_key: "test",
        starts_at: Time.utc(2026, 8, 3), ends_at: Time.utc(2026, 8, 4, 23, 59)
      )
      build_workout(user, date: Date.new(2026, 8, 3))
      build_workout(user, date: Date.new(2026, 8, 10))

      recalculate

      boosted = described_class::WORKOUT_XP * 2
      expect(participation.xp_breakdown["workouts"]).to eq(boosted + described_class::WORKOUT_XP)
    end
  end

  describe "idempotency" do
    it "produces the same result when run repeatedly" do
      3.times { |i| build_workout(user, date: Date.new(2026, 8, 3 + i), km: 6) }

      first = recalculate.xp
      second = recalculate.xp
      third = recalculate.xp

      expect([ second, third ]).to all(eq(first))
    end
  end

  describe "denormalised stats" do
    it "records the values the leaderboards read" do
      build_workout(user, date: Date.new(2026, 8, 3), km: 10, minutes: 50, elevation: 100)
      build_workout(user, date: Date.new(2026, 8, 4), km: 5, minutes: 30, elevation: 50)

      recalculate

      expect(participation.total_distance_km.to_f).to eq(15.0)
      expect(participation.activities_count).to eq(2)
      expect(participation.elevation_gain_m.to_f).to eq(150.0)
      expect(participation.longest_streak_days).to eq(2)
      expect(participation.best_5k_seconds).to eq(1500)
    end
  end

  describe "levelling" do
    it "uses the season's own 30-level curve rather than the global one" do
      participation.update!(xp: 0)
      curve = season.level_curve_object

      expect(curve.max_level).to eq(30)
      expect(curve.level_for(curve.floor_for(20))).to eq(20)
      expect(curve.level_for(curve.floor_for(30))).to eq(30)
    end
  end

  describe "completion percent" do
    let!(:visible) do
      challenge = build_challenge(key: "visible_one", requirements: [ { metric: "activity_count", target: 1 } ])
      season.season_challenges.create!(challenge: challenge, category: "monthly", xp_reward: 100)
    end

    let!(:secret) do
      challenge = build_challenge(key: "secret_one", requirements: [ { metric: "activity_count", target: 1 } ])
      season.season_challenges.create!(challenge: challenge, category: "hidden", hidden: true, xp_reward: 100)
    end

    # Secrets are undiscoverable by definition; counting them in the denominator
    # would make 100% completion impossible to aim at.
    it "excludes hidden challenges from the denominator" do
      participation
      build_workout(user, date: Date.new(2026, 8, 3))
      user.challenge_participations.each { |cp| RecomputeChallengeProgress.new(cp).call }

      recalculate

      expect(participation.completion_percent).to eq(100)
    end
  end

  describe "legacy missions" do
    let!(:mission) do
      season.season_objectives.create!(
        track: "legacy", kind: "legacy", name: "discipline",
        metric: "activity_count", target: 2, xp_reward: 400, fragment_reward: 10
      )
    end

    it "records a completion and its fragments once the target is met" do
      2.times { |i| build_workout(user, date: Date.new(2026, 8, 3 + i)) }

      recalculate

      expect(participation.season_objective_completions.count).to eq(1)
      expect(participation.medal_fragments).to eq(10)
      expect(participation.xp_breakdown["objectives"]).to eq(400)
    end

    it "does not record it twice" do
      2.times { |i| build_workout(user, date: Date.new(2026, 8, 3 + i)) }

      3.times { recalculate }

      expect(participation.season_objective_completions.count).to eq(1)
    end
  end
end
