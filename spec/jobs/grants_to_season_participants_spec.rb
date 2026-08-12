# frozen_string_literal: true

require "rails_helper"

# The batch-and-chain traversal is shared by every payout job, so a cursor bug
# here would silently under-pay a whole community.
RSpec.describe GrantsToSeasonParticipants do
  let(:season) { build_season }

  let!(:goal) do
    season.season_community_goals.create!(
      key: "goal", metric: "distance_km", target_mode: "fixed",
      target_value: 100, base_target_value: 100, tier_coin_reward: 10
    )
  end

  let!(:users) { Array.new(5) { build_user.tap { |u| SeasonProgressService.ensure_participation(u, season) } } }

  # A batch size smaller than the community forces the chain to run.
  before { stub_const("GrantsToSeasonParticipants::BATCH_SIZE", 2) }

  def run_chain(after_id = nil, guard: 10)
    performed = []
    allow(GrantCommunityTierJob).to receive(:perform_later) do |*args|
      performed << args
    end

    GrantCommunityTierJob.new.perform(goal.id, 1, after_id)

    # Follow the chain the way the queue would.
    until performed.empty? || guard.zero?
      guard -= 1
      args = performed.shift
      GrantCommunityTierJob.new.perform(*args)
    end
    guard
  end

  it "pays every participant across the batches" do
    run_chain

    expect(users.map { |u| u.reload.coins }).to all(eq(10))
  end

  it "terminates rather than looping on the last batch" do
    expect(run_chain).to be_positive
  end

  it "pays each participant exactly once" do
    run_chain

    expect(CoinTransaction.where(reason: "community_tier").count).to eq(users.size)
  end

  it "resumes from a cursor without re-paying earlier participants" do
    ordered = season.season_participations.order(:id).to_a
    run_chain(ordered.third.id)

    paid = CoinTransaction.where(reason: "community_tier").pluck(:user_id)
    expect(paid).to match_array(ordered.drop(2).map(&:user_id))
  end
end
