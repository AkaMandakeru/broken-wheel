# frozen_string_literal: true

require "rails_helper"

# A reward every member gets for taking part, optionally narrowed to the people
# who joined inside a window.
RSpec.describe "Participation rewards" do
  # The suite does not wire ActiveJob's helpers globally, and joining enqueues
  # rather than grants inline, so this group drains the queue itself. The
  # Minitest lifecycle hooks TestHelper relies on do not fire under RSpec, hence
  # the explicit clear.
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs and clear_performed_jobs }

  let(:season) { build_season }

  def participation_reward(key: "welcome_banner", from: nil, to: nil, track: "free", **extra)
    season.season_rewards.create!({
      reward_type: "coins", reward_key: key, name: key.humanize, coins: 100,
      unlock_kind: "participation", track: track, joined_from: from, joined_until: to
    }.merge(extra))
  end

  def join(user, at: nil)
    participation = SeasonProgressService.ensure_participation(user, season)
    participation.update_column(:created_at, at) if at
    participation
  end

  def granted?(participation, reward)
    participation.season_reward_grants.exists?(season_reward: reward)
  end

  describe "the model" do
    it "needs no threshold, unlike every other parallel unlock" do
      expect(participation_reward).to be_valid
    end

    it "refuses a window that ends before it starts" do
      reward = season.season_rewards.new(
        reward_type: "coins", reward_key: "backwards", unlock_kind: "participation",
        track: "free", joined_from: 2.days.from_now, joined_until: 1.day.from_now
      )

      expect(reward).not_to be_valid
      expect(reward.errors[:joined_until]).to be_present
    end

    describe "#covers_join?" do
      it "covers everyone when both ends are open" do
        expect(participation_reward.covers_join?(Time.current)).to be(true)
      end

      it "excludes someone who joined before the window opened" do
        reward = participation_reward(from: 2.days.ago)

        expect(reward.covers_join?(5.days.ago)).to be(false)
        expect(reward.covers_join?(1.day.ago)).to be(true)
      end

      it "excludes someone who joined after it closed" do
        reward = participation_reward(to: 2.days.ago)

        expect(reward.covers_join?(1.day.ago)).to be(false)
        expect(reward.covers_join?(5.days.ago)).to be(true)
      end

      it "is false without a join time rather than guessing" do
        expect(participation_reward.covers_join?(nil)).to be(false)
      end
    end
  end

  describe "joining the season" do
    # Proven broken before this: a participation row was created and no reward
    # path ever ran, so someone who joined and never trained got nothing — not
    # even the level-1 reward every member is owed.
    it "grants without the member having to train first" do
      reward = participation_reward
      participation = join(build_user)

      perform_enqueued_jobs

      expect(granted?(participation.reload, reward)).to be(true)
    end

    it "grants the level-1 reward on joining too" do
      level_one = season.season_rewards.create!(
        reward_type: "badge", reward_key: "member", name: "Member",
        unlock_kind: "level", level: 1, track: "free"
      )
      participation = join(build_user)

      perform_enqueued_jobs

      expect(granted?(participation.reload, level_one)).to be(true)
    end

    it "does not grant one whose window has not opened" do
      reward = participation_reward(from: 1.day.from_now)
      participation = join(build_user)

      perform_enqueued_jobs

      expect(granted?(participation.reload, reward)).to be(false)
    end

    it "keeps a premium reward away from a free participant" do
      reward = participation_reward(track: "premium")
      participation = join(build_user)

      perform_enqueued_jobs

      expect(granted?(participation.reload, reward)).to be(false)
    end

    it "grants only once, however often the member is recalculated" do
      reward = participation_reward
      participation = join(build_user)
      3.times { SeasonProgressService.new(participation).recalculate }

      expect(participation.season_reward_grants.where(season_reward: reward).count).to eq(1)
      expect(participation.user.reload.coins).to eq(100)
    end
  end

  describe "handing one out mid-season" do
    let!(:early) { join(build_user, at: 10.days.ago) }
    let!(:late) { join(build_user, at: 1.day.ago) }

    it "reaches everyone when the window is open" do
      reward = participation_reward

      DistributeSeasonRewardJob.perform_now(reward.id)

      expect(granted?(early.reload, reward)).to be(true)
      expect(granted?(late.reload, reward)).to be(true)
    end

    it "reaches only the people who joined inside the window" do
      reward = participation_reward(from: 3.days.ago)

      DistributeSeasonRewardJob.perform_now(reward.id)

      expect(granted?(early.reload, reward)).to be(false)
      expect(granted?(late.reload, reward)).to be(true)
    end

    it "refuses to hand out a reward that has a threshold to clear" do
      level_reward = season.season_rewards.create!(
        reward_type: "coins", reward_key: "lvl5", name: "L5", coins: 50,
        unlock_kind: "level", level: 5, track: "free"
      )

      DistributeSeasonRewardJob.perform_now(level_reward.id)

      expect(granted?(early.reload, level_reward)).to be(false)
    end

    it "is safe to press twice" do
      reward = participation_reward

      2.times { DistributeSeasonRewardJob.perform_now(reward.id) }

      expect(early.reload.season_reward_grants.where(season_reward: reward).count).to eq(1)
      expect(early.user.reload.coins).to eq(100)
    end
  end
end
