# frozen_string_literal: true

require "rails_helper"

# Season weeklies read "15 km AND 4 workouts AND one run over 6 km" — a challenge
# only completes when every requirement is met.
RSpec.describe RecomputeChallengeProgress, "with multiple requirements" do
  let(:user) { build_user }
  let(:season) { build_season }

  let(:challenge) do
    build_challenge(
      key: "week1_beginning",
      sport: "run",
      starts_at: Date.new(2026, 8, 1),
      ends_at: Date.new(2026, 8, 7),
      requirements: [
        { metric: "distance_km",         target: 15 },
        { metric: "activity_count",      target: 4 },
        { metric: "longest_activity_km", target: 6 }
      ]
    )
  end

  let!(:season_challenge) do
    # The week's window lives on the season challenge, which is what lets the
    # same challenge be reused in a later season over that season's dates.
    season.season_challenges.create!(
      challenge: challenge, category: "weekly", xp_reward: 1000, fragment_reward: 10,
      starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7)
    )
  end

  # Enrolled in the season: progress is per season, and a standalone
  # participation deliberately credits no season ledger.
  let(:participation) { ChallengeEnroller.call(user, challenge, season: season) }

  def recompute
    RecomputeChallengeProgress.new(participation.reload).call
    participation.reload
  end

  it "records progress per requirement without completing until all are met" do
    3.times { |i| build_workout(user, date: Date.new(2026, 8, 2 + i), km: 5) }
    recompute

    statuses = participation.requirement_status
    expect(statuses.map { |s| s[:value] }).to eq([ 15.0, 3, 5.0 ])
    expect(statuses.map { |s| s[:met] }).to eq([ true, false, false ])
    expect(participation.completed_at).to be_nil
  end

  it "completes only once every requirement is satisfied" do
    3.times { |i| build_workout(user, date: Date.new(2026, 8, 2 + i), km: 5) }
    recompute
    expect(participation.completed_at).to be_nil

    build_workout(user, date: Date.new(2026, 8, 5), km: 7)
    recompute

    expect(participation.completed_at).to be_present
    expect(participation.percent_complete).to eq(100)
  end

  it "ignores workouts outside the challenge window" do
    4.times { |i| build_workout(user, date: Date.new(2026, 8, 10 + i), km: 8) }
    recompute

    expect(participation.completed_at).to be_nil
    expect(participation.requirement_status.first[:value]).to eq(0.0)
  end

  it "ignores workouts from another sport" do
    4.times { |i| build_workout(user, date: Date.new(2026, 8, 2 + i), km: 8, sport: "bike") }
    recompute

    expect(participation.completed_at).to be_nil
  end

  it "writes a durable season completion and awards XP once" do
    4.times { |i| build_workout(user, date: Date.new(2026, 8, 2 + i), km: 7) }
    SeasonProgressService.ensure_participation(user, season)
    recompute

    season_participation = user.season_participations.find_by(season: season)
    completions = season_participation.season_challenge_completions
    expect(completions.count).to eq(1)
    expect(completions.first.xp_awarded).to eq(1000)

    # Re-running must not double-award.
    recompute
    expect(season_participation.season_challenge_completions.count).to eq(1)
  end

  describe "elite gating" do
    let(:elite_challenge) do
      build_challenge(key: "elite_150", sport: "run", requirements: [ { metric: "distance_km", target: 20 } ])
    end

    let!(:elite_season_challenge) do
      season.season_challenges.create!(challenge: elite_challenge, category: "elite", unlock_level: 20, xp_reward: 1000)
    end

    it "withholds the payout below the unlock level but keeps the progress" do
      season_participation = SeasonProgressService.ensure_participation(user, season)
      participation = ChallengeEnroller.call(user, elite_challenge, season: season)
      3.times { |i| build_workout(user, date: Date.new(2026, 8, 2 + i), km: 8) }

      RecomputeChallengeProgress.new(participation).call

      expect(participation.reload.completed_at).to be_present
      expect(season_participation.season_challenge_completions.count).to eq(0)
    end

    it "pays out once the participant reaches the unlock level" do
      season_participation = SeasonProgressService.ensure_participation(user, season)
      participation = ChallengeEnroller.call(user, elite_challenge, season: season)
      3.times { |i| build_workout(user, date: Date.new(2026, 8, 2 + i), km: 8) }
      RecomputeChallengeProgress.new(participation).call

      season_participation.update!(level: 20)
      participation.update!(completed_at: nil)
      RecomputeChallengeProgress.new(participation.reload).call

      expect(season_participation.season_challenge_completions.count).to eq(1)
    end
  end
end
