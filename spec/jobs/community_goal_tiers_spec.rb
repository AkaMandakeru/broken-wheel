# frozen_string_literal: true

require "rails_helper"

RSpec.describe AggregateCommunityGoalsJob, "escalating tiers" do
  let(:season) { build_season }
  let(:user) { build_user }

  let!(:goal) do
    season.season_community_goals.create!(
      key: "august_marathon", metric: "distance_km",
      target_mode: "fixed", target_value: 100, base_target_value: 100,
      tier_coin_reward: 200
    )
  end

  before do
    SeasonProgressService.ensure_participation(user, season)
    [ 20, 50, 100 ].each { |p| goal.season_community_milestones.create!(tier: 1, percent: p, threshold: p) }
  end

  def log(km, date: Date.new(2026, 8, 5))
    build_workout(user, date: date, km: km)
  end

  def run
    described_class.new.perform(season.id)
    goal.reload
  end

  it "tracks progress inside tier 1" do
    log(40)
    run

    expect(goal.tier).to eq(1)
    expect(goal.effective_target).to eq(100.0)
    expect(goal.tier_progress).to eq(40.0)
    expect(goal.percent_complete).to eq(40)
  end

  it "doubles the target and opens tier 2 when tier 1 is cleared" do
    log(100)
    run

    expect(goal.tier).to eq(2)
    expect(goal.effective_target).to eq(200.0)
    expect(goal.tier_started_value.to_f).to eq(100.0)
    expect(goal.tier_progress).to eq(0.0)
  end

  it "keeps doubling: tier 3 asks for 400" do
    log(100)
    run
    log(200, date: Date.new(2026, 8, 6))
    run

    expect(goal.tier).to eq(3)
    expect(goal.effective_target).to eq(400.0)
  end

  it "clears several tiers at once when a big batch lands" do
    # 100 + 200 + 400 = 700 clears tiers 1, 2 and 3 in a single pass.
    log(700)
    run

    expect(goal.tier).to eq(4)
    expect(goal.effective_target).to eq(800.0)
  end

  it "creates a fresh set of milestones for each new tier" do
    log(100)
    run

    expect(goal.season_community_milestones.for_tier(2).pluck(:percent)).to match_array([ 20, 50, 100 ])
    expect(goal.current_milestones.count).to eq(3)
  end

  it "scales milestone thresholds with the doubled target" do
    log(100)
    run
    half = goal.current_milestones.find_by(percent: 50)

    expect(half.effective_threshold).to eq(100.0) # 50% of tier 2's 200
  end

  it "pays every participant, scaled by tier" do
    log(100)
    run
    perform_enqueued_jobs_now

    expect(user.reload.coins).to eq(200) # tier 1 × 200

    log(200, date: Date.new(2026, 8, 6))
    run
    perform_enqueued_jobs_now

    expect(user.reload.coins).to eq(200 + 400) # tier 2 × 200
  end

  it "does not pay twice for the same tier" do
    log(100)
    run
    3.times { perform_enqueued_jobs_now }

    expect(user.reload.coins).to eq(200)
    expect(user.coin_transactions.where(reason: "community_tier").count).to eq(1)
  end

  it "records an activity naming the next tier" do
    log(100)
    run

    activity = season.season_activities.find_by(kind: "community_tier_cleared")
    expect(activity).to be_present
    expect(activity.user_id).to be_nil # belongs to the community, not one runner
    expect(activity.metadata["tier"]).to eq(1)
    expect(activity.metadata["next_target"].to_f).to eq(200.0)
  end

  it "is idempotent — re-running without new workouts changes nothing" do
    log(100)
    run
    tier_after_first = goal.tier

    3.times { run }

    expect(goal.tier).to eq(tier_after_first)
    expect(season.season_activities.where(kind: "community_tier_cleared").count).to eq(1)
  end

  it "stops escalating at max_tiers when one is set" do
    goal.update!(max_tiers: 2)
    log(1000)
    run

    expect(goal.tier).to eq(2)
  end

  it "scales the base target to the community when configured per participant" do
    goal.update!(target_mode: "per_participant", per_participant: 60, tier: 1, tier_started_value: 0)
    2.times { SeasonProgressService.ensure_participation(build_user, season) }

    expect(goal.reload.base_target).to eq(180.0) # 3 participants × 60
    expect(goal.effective_target).to eq(180.0)
  end

  # Guards the bounded advance loop against a misconfigured goal.
  it "does not spin forever on a zero target" do
    goal.update!(target_value: 100, base_target_value: 0, target_mode: "fixed")
    log(50)

    expect { run }.not_to raise_error
    expect(goal.tier).to eq(1)
  end

  # Runs the payout for every tier cleared so far, the way the enqueued jobs
  # would. Calling it repeatedly is exactly the retry case worth testing.
  def perform_enqueued_jobs_now
    (1...goal.reload.tier).each { |cleared| GrantCommunityTierJob.new.perform(goal.id, cleared) }
  end
end
