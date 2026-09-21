# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeasonSandbox do
  let(:user) { build_user }
  # August 2026, seen from mid-July: a season that has not started yet, which is
  # the case the sandbox exists for.
  let(:season) { build_season(status: "upcoming") }
  let(:sandbox) { described_class.new(season, user) }

  let(:ten_k) { build_challenge(key: "ten_k_#{SecureRandom.hex(2)}", requirements: [ { metric: "distance_km", target: 10 } ]) }
  let!(:season_challenge) do
    season.season_challenges.create!(challenge: ten_k, xp_reward: 200, coin_reward: 15, fragment_reward: 30)
  end

  around { |example| travel_to(Time.zone.local(2026, 7, 15, 12)) { example.run } }

  def reward(level:, track: "free", type: "badge", key: "reward-#{SecureRandom.hex(3)}", **extra)
    season.season_rewards.create!({ level: level, track: track, reward_type: type, reward_key: key, name: key.humanize }.merge(extra))
  end

  describe ".enabled?" do
    it "is off in the test environment unless switched on" do
      expect(described_class.enabled?).to be(false)
    end

    it "follows SEASON_SANDBOX_ENABLED outside development" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SEASON_SANDBOX_ENABLED").and_return("true")

      expect(described_class.enabled?).to be(true)
    end
  end

  describe "#generate_workouts!" do
    it "spreads marked workouts over the season and scores them before it starts" do
      sandbox.generate_workouts!(count: 10, min_km: 5, max_km: 5)

      workouts = user.workouts.where(provider: described_class::WORKOUT_PROVIDER)
      expect(workouts.count).to eq(10)
      expect(workouts.pluck(:workout_date)).to all(be_between(Date.new(2026, 8, 1), Date.new(2026, 8, 31)))
      expect(workouts.pluck(:start_time_known)).to all(be(true))

      participation = sandbox.participation
      expect(participation.activities_count).to eq(10)
      expect(participation.xp).to be >= 10 * SeasonProgressService::WORKOUT_XP
    end

    # A real season only records completions while it is active. The sandbox
    # records them regardless — unclaimed, the way a player would find them.
    it "records the challenges the workouts finish, waiting to be claimed" do
      sandbox.generate_workouts!(count: 3, min_km: 5, max_km: 5)

      completion = sandbox.participation.season_challenge_completions.sole
      expect(completion.season_challenge).to eq(season_challenge)
      expect(completion).not_to be_claimed
    end

    it "keeps to the dates asked for" do
      sandbox.generate_workouts!(count: 4, from: "2026-08-10", to: "2026-08-11")

      expect(user.workouts.pluck(:workout_date).uniq).to contain_exactly(Date.new(2026, 8, 10), Date.new(2026, 8, 11))
    end

    it "refuses dates outside the season" do
      expect { sandbox.generate_workouts!(count: 1, from: "2026-10-01", to: "2026-10-05") }
        .to raise_error(described_class::Error)
    end
  end

  describe "#complete_challenges!" do
    it "pays XP, coins and fragments like a real completion" do
      sandbox.complete_challenges!(claim: true)

      participation = sandbox.participation
      expect(participation.season_challenge_completions.claimed.count).to eq(1)
      expect(participation.xp_breakdown["challenges"]).to eq(200)
      expect(participation.medal_fragments).to eq(30)
      expect(user.reload.coins).to eq(15)
      expect(user.challenge_participations.find_by(season: season, challenge: ten_k)).to be_completed
    end

    it "leaves the XP to claim when asked to" do
      sandbox.complete_challenges!(claim: false)

      expect(sandbox.participation.unclaimed_xp).to eq(200)
      expect(sandbox.participation.xp_breakdown["challenges"]).to eq(0)
    end

    it "only completes the ones picked" do
      other = season.season_challenges.create!(
        challenge: build_challenge(key: "other_#{SecureRandom.hex(2)}", requirements: [ { metric: "activity_count", target: 3 } ]),
        xp_reward: 50
      )

      sandbox.complete_challenges!(ids: [ other.id ])

      expect(sandbox.participation.season_challenge_completions.pluck(:season_challenge_id)).to eq([ other.id ])
    end

    it "does not pay twice when run again" do
      2.times { sandbox.complete_challenges!(claim: true) }

      expect(user.reload.coins).to eq(15)
      expect(sandbox.participation.season_challenge_completions.count).to eq(1)
    end
  end

  describe "#set_level!" do
    it "puts the player on the level and grants the rewards on the way" do
      below = reward(level: 5)
      at = reward(level: 10)
      above = reward(level: 11)

      sandbox.set_level!(10)

      participation = sandbox.participation
      expect(participation.level).to eq(10)
      expect(participation.granted_reward_ids).to include(below.id, at.id)
      expect(participation.granted_reward_ids).not_to include(above.id)
    end

    it "accounts for the season's XP multiplier" do
      season.update!(xp_multiplier: 1.5)

      sandbox.set_level!(12)

      expect(sandbox.participation.level).to eq(12)
    end

    it "survives a later recalculation" do
      sandbox.set_level!(8)
      SeasonProgressService.new(sandbox.participation).recalculate

      expect(sandbox.participation.reload.level).to eq(8)
    end
  end

  describe "#set_premium!" do
    it "grants the premium rewards already unlocked" do
      premium = reward(level: 3, track: "premium")
      sandbox.set_level!(5)
      expect(sandbox.participation.granted_reward_ids).not_to include(premium.id)

      sandbox.set_premium!(true)

      expect(sandbox.participation).to be_premium
      expect(sandbox.participation.granted_reward_ids).to include(premium.id)
    end
  end

  describe "#grant_reward!" do
    it "grants one reward regardless of its unlock rule" do
      medal = season.season_rewards.create!(
        unlock_kind: "medal_fragments", unlock_value: 200, reward_type: "title", reward_key: "champion", name: "Champion"
      )

      sandbox.grant_reward!(medal)

      expect(sandbox.participation.granted_reward_ids).to eq([ medal.id ])
      expect(user.reload.title?(:champion)).to be(true)
    end
  end

  describe "#complete_dailies!" do
    it "completes the draw for the first days of a season that has not started" do
      season.daily_challenge_templates.create!(key: "run_3k", metric: "distance_km", target: 3, xp_reward: 50, coin_reward: 5)
      season.daily_challenge_templates.create!(key: "run_once", metric: "activity_count", target: 1, xp_reward: 40, coin_reward: 5)

      completed = sandbox.complete_dailies!(days: 3)

      assignments = DailyChallengeAssignment.where(user: user, season: season)
      expect(completed).to eq(6)
      expect(assignments.pluck(:challenge_date).uniq).to contain_exactly(*Date.new(2026, 8, 1)..Date.new(2026, 8, 3))
      expect(assignments.pending).to be_empty
      expect(sandbox.participation.xp_breakdown["dailies"]).to eq(3 * 90)
    end

    it "says so when there is nothing to draw from" do
      expect { sandbox.complete_dailies!(days: 1) }.to raise_error(described_class::Error)
    end
  end

  describe "#complete_objectives!" do
    it "records the objectives with their XP" do
      season.season_objectives.create!(kind: "legacy", track: "legacy", name: "Discipline", target: 99, xp_reward: 300)

      sandbox.complete_objectives!

      expect(sandbox.participation.season_objective_completions.count).to eq(1)
      expect(sandbox.participation.xp_breakdown["objectives"]).to eq(300)
    end
  end

  describe "#reset!" do
    it "takes the player back to before the season, keeping real workouts" do
      real = build_workout(user, date: Date.new(2026, 8, 5))
      title = season.season_rewards.create!(level: 2, reward_type: "title", reward_key: "champion", name: "Champion")
      coins = reward(level: 3, type: "coins", coins: 100)
      sandbox.generate_workouts!(count: 5)
      sandbox.complete_challenges!
      sandbox.set_level!(4)
      expect(user.reload.title?(:champion)).to be(true)
      expect(user.coins).to be >= 115

      sandbox.reset!

      user.reload
      expect(season.season_participations.where(user: user)).to be_empty
      expect(user.workouts).to eq([ real ])
      expect(user.challenge_participations.where(season: season)).to be_empty
      expect(user.coins).to eq(0)
      expect(user.coin_transactions).to be_empty
      expect(user.title?(:champion)).to be(false)
      expect(SeasonRewardGrant.where(season_reward: [ title, coins ])).to be_empty
      expect(season.season_activities.where(user: user)).to be_empty
    end

    it "lets the player start the season again afterwards" do
      sandbox.complete_challenges!
      sandbox.reset!

      sandbox.complete_challenges!

      expect(user.reload.coins).to eq(15)
    end
  end

  describe "bots" do
    it "adds runners to the season and removes every trace of them" do
      bots = described_class.add_bots!(season, count: 3, random: Random.new(1))

      expect(bots.map(&:email)).to all(end_with("@#{described_class::BOT_EMAIL_DOMAIN}"))
      expect(season.season_participations.where(user: bots).count).to eq(3)

      expect(described_class.remove_bots!).to eq(3)
      expect(User.where(id: bots.map(&:id))).to be_empty
      expect(Workout.where(user_id: bots.map(&:id))).to be_empty
      expect(season.season_participations.count).to eq(0)
    end

    it "never counts a real account as a bot" do
      expect(described_class.bot?(user)).to be(false)
      expect(described_class.bots).not_to include(user)
    end
  end
end
