# frozen_string_literal: true

require "rails_helper"

# The blueprint is the repeatability guarantee: September should be one YAML
# file, and re-importing must never duplicate or destroy anything.
RSpec.describe Seasons::BlueprintImporter do
  let(:key) { "season_8_legacy_of_champions" }

  it "imports the reference season with all of its content" do
    season = described_class.call(key)

    expect(season.key).to eq(key)
    expect(season.max_level).to eq(10)
    expect(season.level_curve.size).to eq(10)
    expect(season.level_curve.last).to eq(season.top_level_xp)
    expect(season.theme).to eq("legacy")
    expect(season.time_zone).to eq("America/Sao_Paulo")

    expect(season.season_challenges.of_category("weekly").count).to eq(4)
    expect(season.season_challenges.of_category("monthly").count).to eq(4)
    expect(season.season_challenges.of_category("elite").count).to eq(5)
    expect(season.season_challenges.secret.count).to eq(6)
    expect(season.season_objectives.legacy.count).to eq(5)
    expect(season.season_community_goals.count).to eq(1)
    expect(DailyChallengeTemplate.where(season: season).count).to eq(12)
  end

  it "builds compound weekly requirements" do
    described_class.call(key)
    week1 = Challenge.find_by(key: "s8_week1_beginning")

    expect(week1.challenge_requirements.map(&:metric))
      .to eq(%w[distance_km activity_count longest_activity_km])
    expect(week1.challenge_requirements.map { |r| r.target.to_f }).to eq([ 15.0, 4.0, 6.0 ])
  end

  it "seeds season content as custom challenges so the weekly reset cannot wipe it" do
    described_class.call(key)

    weekly_keys = Challenge.where(key: %w[s8_week1_beginning s8_week2_momentum s8_week3_endurance s8_week4_champion])
    expect(weekly_keys.pluck(:challenge_type).uniq).to eq([ "custom" ])
  end

  it "is idempotent — a second import changes no counts" do
    season = described_class.call(key)
    counts = {
      challenges: season.season_challenges.count,
      rewards: season.season_rewards.count,
      objectives: season.season_objectives.count,
      requirements: ChallengeRequirement.count,
      cosmetics: Cosmetic.count,
      dailies: DailyChallengeTemplate.count,
      milestones: SeasonCommunityMilestone.count
    }

    described_class.call(key)
    season.reload

    expect(season.season_challenges.count).to eq(counts[:challenges])
    expect(season.season_rewards.count).to eq(counts[:rewards])
    expect(season.season_objectives.count).to eq(counts[:objectives])
    expect(ChallengeRequirement.count).to eq(counts[:requirements])
    expect(Cosmetic.count).to eq(counts[:cosmetics])
    expect(DailyChallengeTemplate.count).to eq(counts[:dailies])
    expect(SeasonCommunityMilestone.count).to eq(counts[:milestones])
    expect(Season.where(key: key).count).to eq(1)
  end

  it "preserves player progress across a re-import" do
    season = described_class.call(key)
    user = build_user
    participation = SeasonProgressService.ensure_participation(user, season)
    participation.update!(xp: 4200, level: 12)

    described_class.call(key)

    expect(participation.reload.xp).to eq(4200)
    expect(participation.level).to eq(12)
  end

  it "separates the free and premium reward tracks" do
    season = described_class.call(key)

    expect(season.season_rewards.where(track: "premium", unlock_kind: "level")).to be_any
    expect(season.season_rewards.where(track: "free", unlock_kind: "level")).to be_any
    expect(season.season_rewards.find_by(unlock_kind: "legacy").unlock_value).to eq(5)
  end

  it "sizes the community goal per participant" do
    season = described_class.call(key)
    goal = season.season_community_goals.first

    expect(goal.target_mode).to eq("per_participant")
    expect(goal.effective_target).to eq(60.0)
  end

  # The target is frozen when a tier opens. Recomputing it live would drag every
  # player's bar backwards the moment someone new joined.
  it "holds the tier's target steady as the community grows" do
    season = described_class.call(key)
    goal = season.season_community_goals.first
    goal.effective_target # freeze at today's size

    3.times { SeasonProgressService.ensure_participation(build_user, season) }

    expect(goal.reload.effective_target).to eq(60.0)
  end

  it "sizes the next tier to the community as it stands then" do
    season = described_class.call(key)
    goal = season.season_community_goals.first
    3.times { SeasonProgressService.ensure_participation(build_user, season) }

    goal.update!(tier: 2)
    goal.freeze_tier_target!

    # 3 participants x 60 = 180 base, doubled for tier 2.
    expect(goal.reload.effective_target).to eq(360.0)
  end

  it "raises a clear error for an unknown blueprint" do
    expect { described_class.call("nope") }.to raise_error(described_class::MissingBlueprint, /nope/)
  end
end
