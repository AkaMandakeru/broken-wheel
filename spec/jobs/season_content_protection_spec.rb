# frozen_string_literal: true

require "rails_helper"

# A season's "Week 1 — The Beginning" is a fixed, one-off challenge. The weekly
# reset job exists to roll *recurring* challenges forward; if it ever touched
# season content it would erase each named week the moment it ended.
RSpec.describe ResetWeeklyChallengesJob, "season content protection" do
  let(:user) { build_user }
  let(:season) { build_season }

  let(:recurring) do
    Challenge.create!(
      key: "recurring_weekly", title: "Weekly 20km", challenge_type: "weekly", sport: "run",
      target_value: 20, target_unit: "km", status: "active",
      starts_at: 3.weeks.ago.beginning_of_week(:sunday), ends_at: 3.weeks.ago.end_of_week(:sunday)
    )
  end

  let(:season_weekly) do
    Challenge.create!(
      key: "s_week1", title: "Week 1", challenge_type: "weekly", sport: "run",
      target_value: 15, target_unit: "km", status: "active",
      starts_at: Date.new(2026, 8, 1), ends_at: Date.new(2026, 8, 7)
    )
  end

  it "rolls a recurring weekly challenge forward and clears its progress" do
    participation = ChallengeParticipation.create!(challenge: recurring, user: user, progress_value: 12)

    described_class.new.perform

    expect(participation.reload.progress_value.to_f).to eq(0.0)
    expect(recurring.reload.starts_at.to_date).to eq(Challenge.current_week_window.begin)
  end

  it "leaves a season-attached weekly challenge untouched" do
    season.season_challenges.create!(challenge: season_weekly, category: "weekly", xp_reward: 1000)
    participation = ChallengeParticipation.create!(challenge: season_weekly, user: user, progress_value: 12)

    described_class.new.perform

    expect(participation.reload.progress_value.to_f).to eq(12.0)
    expect(season_weekly.reload.starts_at.to_date).to eq(Date.new(2026, 8, 1))
    expect(season_weekly.ends_at.to_date).to eq(Date.new(2026, 8, 7))
  end

  it "clears stale requirement progress when it does reset a challenge" do
    recurring.challenge_requirements.create!(metric: "distance_km", target: 20)
    participation = ChallengeParticipation.create!(
      challenge: recurring, user: user, progress_value: 12,
      requirement_progress: { "1" => 12.0 }, completed_at: Time.current
    )

    described_class.new.perform

    expect(participation.reload.requirement_progress).to eq({})
    expect(participation.completed_at).to be_nil
  end
end
