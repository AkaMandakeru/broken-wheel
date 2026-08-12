# frozen_string_literal: true

require "rails_helper"

RSpec.describe Season, "deletion" do
  let(:user) { build_user }
  let(:season) { build_season }

  # Season-scoped challenge progress is owned by the season. Without that
  # ownership the foreign key blocks deletion once anyone has taken part.
  it "removes its challenge participations" do
    challenge = build_challenge(key: "owned", requirements: [ { metric: "distance_km", target: 5 } ])
    season.season_challenges.create!(challenge: challenge, category: "monthly", xp_reward: 100)
    SeasonProgressService.ensure_participation(user, season)
    ChallengeEnroller.call(user, challenge, season: season)

    expect { season.destroy! }.to change { user.challenge_participations.count }.by(-1)
  end

  # Season destroys its rewards before its community goals, so a milestone
  # pointing at a reward would otherwise block the delete on a foreign key.
  it "can be deleted when a community milestone grants one of its rewards" do
    reward = season.season_rewards.create!(
      reward_type: "badge", reward_key: "community_badge",
      unlock_kind: "community", unlock_value: 100
    )
    goal = season.season_community_goals.create!(
      key: "goal", metric: "distance_km", target_mode: "fixed", target_value: 100
    )
    goal.season_community_milestones.create!(tier: 1, percent: 100, threshold: 100, season_reward: reward)

    expect { season.destroy! }.not_to raise_error
    expect(SeasonCommunityMilestone.count).to eq(0)
  end

  it "leaves standalone participations alone" do
    challenge = build_challenge(key: "solo", requirements: [ { metric: "distance_km", target: 5 } ])
    standalone = ChallengeEnroller.call(user, challenge)

    season.destroy!

    expect(ChallengeParticipation.exists?(standalone.id)).to be(true)
  end
end
