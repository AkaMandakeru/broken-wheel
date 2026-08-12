# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyChallenges::Assigner do
  let(:user) { build_user }
  let(:season) { build_season }
  let(:date) { Date.new(2026, 8, 10) }

  before do
    SeasonProgressService.ensure_participation(user, season)
    %w[run_3km one_activity beat_yesterday burn_300kcal no_stopping].each do |key|
      DailyChallengeTemplate.create!(
        season: season, key: key, metric: "activity_count", target: 1, xp_reward: 50, coin_reward: 25
      )
    end
  end

  it "assigns exactly three challenges" do
    expect(described_class.call(user, season, date: date).size).to eq(3)
  end

  # The job and a lazy page visit both assign; if they disagreed, a user could
  # watch their dailies change under them.
  it "is deterministic for the same user and day" do
    first = described_class.call(user, season, date: date).map(&:daily_challenge_template_id).sort
    DailyChallengeAssignment.delete_all
    second = described_class.call(user, season, date: date).map(&:daily_challenge_template_id).sort

    expect(second).to eq(first)
  end

  # The seed is per (user, season, day), so draws must vary between users. Two
  # users can legitimately collide by chance, so this asserts across a group —
  # every one of them drawing the same three would mean the seed ignores the user.
  it "varies the draw between users" do
    draws = Array.new(8) do
      other = build_user
      SeasonProgressService.ensure_participation(other, season)
      described_class.call(other, season, date: date).map(&:daily_challenge_template_id).sort
    end

    expect(draws.uniq.size).to be > 1
  end

  it "does not duplicate on a second run" do
    described_class.call(user, season, date: date)
    described_class.call(user, season, date: date)

    expect(DailyChallengeAssignment.where(user: user, challenge_date: date).count).to eq(3)
  end

  it "assigns nothing outside the season window" do
    expect(described_class.call(user, season, date: Date.new(2026, 9, 15))).to be_empty
  end

  describe "clock-dependent templates" do
    before do
      DailyChallengeTemplate.where(season: season).destroy_all
      DailyChallengeTemplate.create!(
        season: season, key: "before_8am", metric: "start_before_hour",
        target: 1, options: { hour: 8 }, requires_start_time: true
      )
      DailyChallengeTemplate.create!(season: season, key: "one_activity", metric: "activity_count", target: 1)
    end

    # Handing an hour-based daily to someone whose workouts carry no clock time
    # is handing them a challenge they cannot win.
    it "withholds them from users whose workouts have no start time" do
      build_workout(user, date: date, known_time: false)

      keys = described_class.call(user, season, date: date).map { |a| a.daily_challenge_template.key }
      expect(keys).to all(eq("one_activity"))
    end

    it "offers them once the user has timed workouts" do
      build_workout(user, date: date, known_time: true, hour: 7)

      keys = described_class.call(user, season, date: date).map { |a| a.daily_challenge_template.key }
      expect(keys).to include("before_8am")
    end
  end
end

RSpec.describe DailyChallenges::Evaluator do
  let(:user) { build_user }
  let(:season) { build_season }
  let(:participation) { SeasonProgressService.ensure_participation(user, season) }
  let(:today) { season.current_date }

  let!(:template) do
    DailyChallengeTemplate.create!(
      season: season, key: "run_3km", metric: "distance_km", target: 3, xp_reward: 50, coin_reward: 25
    )
  end

  def assign(date)
    DailyChallengeAssignment.create!(
      user: user, season: season, daily_challenge_template: template, challenge_date: date
    )
  end

  it "completes an assignment whose target was met and pays XP and coins" do
    assignment = assign(today)
    build_workout(user, date: today, km: 4)

    described_class.new(participation).call

    expect(assignment.reload).to be_completed
    expect(assignment.xp_awarded).to eq(50)
    expect(user.reload.coins).to eq(25)
  end

  it "leaves an unmet assignment pending" do
    assignment = assign(today)
    build_workout(user, date: today, km: 1)

    described_class.new(participation).call

    expect(assignment.reload).not_to be_completed
  end

  # Strava imports routinely land hours after the run; expiring a daily at
  # midnight would punish the user for the provider being slow.
  it "still credits yesterday's daily when the data arrives late" do
    assignment = assign(today - 1)
    build_workout(user, date: today - 1, km: 4)

    described_class.new(participation).call

    expect(assignment.reload).to be_completed
  end

  it "does not pay twice" do
    assign(today)
    build_workout(user, date: today, km: 4)

    2.times { described_class.new(participation).call }

    expect(user.reload.coins).to eq(25)
    expect(user.coin_transactions.count).to eq(1)
  end
end
