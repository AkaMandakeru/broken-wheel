# frozen_string_literal: true

require "rails_helper"

# The season funnel is only measurable if every step of it emits an event, and
# none of it is recoverable after the fact — so each call site is pinned here.
RSpec.describe "Season analytics" do
  let(:user) { build_user }
  let(:season) { build_season(max_level: 10, top_level_xp: 1000) }

  def events(name)
    AnalyticsEvent.where(user: user, event_name: name)
  end

  def properties(name)
    events(name).last.properties
  end

  describe "joining" do
    it "records the join with the season key" do
      SeasonProgressService.ensure_participation(user, season)

      expect(events("season_joined").count).to eq(1)
      expect(properties("season_joined")).to include("season_key" => season.key)
    end

    # This runs on every season page view. Tracking the re-fetch would turn one
    # join into a daily event and destroy the D1/D7 return numbers.
    it "does not record again when the participation already exists" do
      3.times { SeasonProgressService.ensure_participation(user, season) }

      expect(events("season_joined").count).to eq(1)
    end
  end

  describe "completing and claiming a challenge" do
    let(:participation) { SeasonProgressService.ensure_participation(user, season) }

    let(:challenge) do
      build_challenge(key: "run_20km", sport: "run", requirements: [ { metric: "distance_km", target: 20 } ])
    end

    let!(:season_challenge) do
      season.season_challenges.create!(challenge: challenge, category: "monthly", xp_reward: 500)
    end

    before do
      participation
      ChallengeEnroller.call(user, challenge, season: season)
      3.times { |i| build_workout(user, date: Date.new(2026, 8, 3 + i), km: 8) }
      RecomputeChallengeProgress.new(
        user.challenge_participations.find_by(challenge: challenge, season: season)
      ).call
      SeasonProgressService.new(participation).recalculate
    end

    it "records the completion with its challenge key and category" do
      expect(events("season_challenge_completed").count).to eq(1)
      expect(properties("season_challenge_completed")).to include(
        "season_key" => season.key, "challenge_key" => "run_20km",
        "category" => "monthly", "xp" => 500, "hidden" => false
      )
    end

    it "records the claim separately from the completion" do
      SeasonXpClaimer.new(participation.reload).call

      expect(properties("season_xp_claimed")).to include(
        "season_key" => season.key, "claimed_count" => 1, "xp" => 500
      )
    end

    # A claim that collects nothing would otherwise flatten the completion →
    # claim conversion rate, which is the headline number of the beta.
    it "records nothing when there is nothing to claim" do
      SeasonXpClaimer.new(participation.reload).call
      expect { SeasonXpClaimer.new(participation.reload).call }
        .not_to change { events("season_xp_claimed").count }
    end

    it "records the level up the claim caused" do
      SeasonXpClaimer.new(participation.reload).call

      expect(events("season_level_up")).to be_present
      expect(properties("season_level_up")).to include("season_key" => season.key)
    end
  end

  describe "granting a reward" do
    let(:participation) { SeasonProgressService.ensure_participation(user, season) }

    let!(:reward) do
      season.season_rewards.create!(
        level: 1, unlock_value: 1, track: "free", unlock_kind: "level",
        reward_type: "coins", reward_key: "s_coins", name: "100 Moedas", coins: 100
      )
    end

    it "records the reward key, type and track" do
      SeasonRewardGranter.new(participation).grant_for_level(1)

      expect(properties("season_reward_granted")).to include(
        "season_key" => season.key, "reward_key" => "s_coins",
        "reward_type" => "coins", "track" => "free", "unlock_kind" => "level"
      )
    end

    it "does not record a second time for an already-granted reward" do
      2.times { SeasonRewardGranter.new(participation).grant_for_level(1) }

      expect(events("season_reward_granted").count).to eq(1)
    end
  end

  describe "daily challenges" do
    let(:season) { build_season(max_level: 10, top_level_xp: 1000, starts_at: Date.current - 5, ends_at: Date.current + 5) }
    let(:today) { season.current_date }

    let!(:template) do
      season.daily_challenge_templates.create!(
        key: "movimento_do_dia", metric: "activity_count", target: 1,
        sport: "run", weight: 1, xp_reward: 50, coin_reward: 25
      )
    end

    it "records the assignment with the template key" do
      DailyChallenges::Assigner.call(user, season, date: today)

      expect(properties("season_daily_assigned")).to include(
        "season_key" => season.key, "template_key" => "movimento_do_dia",
        "challenge_date" => today.to_s
      )
    end

    # Assignment is deterministic and re-runs on every page visit; only the
    # first one is a real event.
    it "does not record the same day twice" do
      2.times { DailyChallenges::Assigner.call(user, season, date: today) }

      expect(events("season_daily_assigned").count).to eq(1)
    end

    it "records the completion once the daily is satisfied" do
      participation = SeasonProgressService.ensure_participation(user, season)
      DailyChallenges::Assigner.call(user, season, date: today)
      build_workout(user, date: today, km: 5)

      DailyChallenges::Evaluator.new(participation.reload).call

      expect(properties("season_daily_completed")).to include(
        "season_key" => season.key, "template_key" => "movimento_do_dia", "xp" => 50
      )
    end
  end

  describe "clearing a community tier" do
    let!(:participation) { SeasonProgressService.ensure_participation(user, season) }

    let!(:goal) do
      season.season_community_goals.create!(
        key: "brasil_em_movimento", metric: "distance_km", target_mode: "fixed",
        target_value: 100, tier: 1, tier_coin_reward: 200
      )
    end

    # The tier is a season-wide event but Analytics is keyed to a user, so it is
    # recorded against each participant the payout actually reached.
    it "records it against every participant paid" do
      GrantCommunityTierJob.perform_now(goal.id, 1)

      expect(properties("season_community_tier_cleared")).to include(
        "season_key" => season.key, "tier" => 1, "payout" => 200
      )
    end
  end
end
