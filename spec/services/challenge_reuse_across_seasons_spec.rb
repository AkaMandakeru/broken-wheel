# frozen_string_literal: true

require "rails_helper"

# Progress used to be global per (user, challenge), so attaching a challenge to a
# second season carried the first season's progress over — it could show as
# already finished in a brand-new season, and never award that season's XP,
# because completion only fires on the transition to finished.
RSpec.describe "Reusing a challenge across seasons" do
  let(:user) { build_user }

  let(:august) do
    build_season(key: "august", starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 31))
  end

  let(:september) do
    build_season(key: "september", starts_at: Date.new(2026, 9, 1), ends_at: Date.new(2026, 9, 30))
  end

  let(:challenge) do
    build_challenge(
      key: "run_30km", sport: "run",
      starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 31),
      requirements: [ { metric: "distance_km", target: 30 } ]
    )
  end

  def attach(season, **attrs)
    season.season_challenges.create!({ challenge: challenge, category: "monthly", xp_reward: 500 }.merge(attrs))
  end

  def enroll(season)
    SeasonProgressService.ensure_participation(user, season)
    ChallengeEnroller.call(user, challenge, season: season)
  end

  def participation_in(season)
    user.challenge_participations.find_by(challenge: challenge, season: season)
  end

  before do
    attach(august)
    # A finished August: 40 km across four runs.
    4.times { |i| build_workout(user, date: Date.new(2026, 8, 3 + i), km: 10) }
    enroll(august)
    RecomputeChallengeProgress.new(participation_in(august)).call
  end

  it "finishes in the season the work was done in" do
    expect(participation_in(august).completed_at).to be_present
    expect(participation_in(august).progress_value.to_f).to eq(40.0)
  end

  it "starts empty when the same challenge is added to a new season" do
    attach(september)
    enroll(september)

    fresh = participation_in(september)
    expect(fresh.completed_at).to be_nil
    expect(fresh.progress_value.to_f).to eq(0.0)
    expect(fresh.requirement_status.map { |s| s[:value] }).to eq([ 0.0 ])
  end

  it "keeps the original season's progress intact" do
    attach(september)
    enroll(september)

    expect(participation_in(august).completed_at).to be_present
    expect(participation_in(august).progress_value.to_f).to eq(40.0)
  end

  it "scores the new season over the new season's dates" do
    attach(september)
    enroll(september)

    expect(participation_in(september).window).to eq(Date.new(2026, 9, 1)..Date.new(2026, 9, 30))
    expect(participation_in(august).window).to eq(Date.new(2026, 8, 1)..Date.new(2026, 8, 31))
  end

  it "ignores the old season's workouts in the new season" do
    attach(september)
    enroll(september)
    build_workout(user, date: Date.new(2026, 9, 2), km: 12)
    RecomputeChallengeProgress.new(participation_in(september)).call

    expect(participation_in(september).progress_value.to_f).to eq(12.0)
  end

  # The second half of the bug: because the participation already read as
  # completed, the new season's ledger never received a completion, so the work
  # was worth nothing there.
  it "awards the new season's XP when the work is repeated" do
    september_challenge = attach(september)
    september_participation = SeasonProgressService.ensure_participation(user, september)
    enroll(september)

    3.times { |i| build_workout(user, date: Date.new(2026, 9, 4 + i), km: 11) }
    RecomputeChallengeProgress.new(participation_in(september)).call

    completions = september_participation.season_challenge_completions
    expect(completions.count).to eq(1)
    expect(completions.first.season_challenge_id).to eq(september_challenge.id)
    expect(completions.first.xp_awarded).to eq(500)
  end

  it "does not credit the old season a second time" do
    attach(september)
    august_participation = user.season_participations.find_by(season: august)
    before = august_participation.season_challenge_completions.count

    enroll(september)
    3.times { |i| build_workout(user, date: Date.new(2026, 9, 4 + i), km: 11) }
    RecomputeChallengeProgress.new(participation_in(september)).call

    expect(august_participation.season_challenge_completions.count).to eq(before)
  end

  it "keeps one participation per season" do
    attach(september)
    enroll(september)
    3.times { enroll(september) } # re-enrolling must not duplicate

    expect(user.challenge_participations.where(challenge: challenge).count).to eq(2)
  end

  describe "the season challenge window" do
    it "defaults to the whole season when left blank" do
      season_challenge = attach(september)

      expect(season_challenge.date_window).to eq(september.date_window)
    end

    it "can carve out a narrower slice, which is how the named weeks work" do
      season_challenge = attach(september, starts_at: Date.new(2026, 9, 1), ends_at: Date.new(2026, 9, 7))

      expect(season_challenge.date_window).to eq(Date.new(2026, 9, 1)..Date.new(2026, 9, 7))
    end

    # Usually a sign the dates were copied from the season it came from.
    it "rejects a window outside the season" do
      season_challenge = september.season_challenges.new(
        challenge: challenge, category: "monthly",
        starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7)
      )

      expect(season_challenge).not_to be_valid
    end
  end

  describe "standalone challenges" do
    let(:solo) { build_challenge(key: "solo", requirements: [ { metric: "activity_count", target: 1 } ]) }

    it "keeps working outside any season" do
      participation = ChallengeEnroller.call(user, solo)

      expect(participation.season_id).to be_nil
      expect(ChallengeEnroller.call(user, solo)).to eq(participation)
    end

    it "is separate from the same challenge run inside a season" do
      standalone = ChallengeEnroller.call(user, solo)
      august.season_challenges.create!(challenge: solo, category: "monthly", xp_reward: 100)
      in_season = ChallengeEnroller.call(user, solo, season: august)

      expect(in_season.id).not_to eq(standalone.id)
      expect(user.challenge_participations.standalone.where(challenge: solo).count).to eq(1)
    end
  end
end
