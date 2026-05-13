# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResetWeeklyChallengesJob, type: :job do
  let(:user) do
    User.create!(
      first_name: "Reset",
      last_name: "Tester",
      email: "reset-tester-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  let!(:weekly_challenge) do
    Challenge.create!(
      title: "Weekly Run 20km",
      description: "Run 20km this week",
      challenge_type: "weekly",
      sport: "run",
      target_value: 20,
      target_unit: "km",
      starts_at: 2.weeks.ago.beginning_of_week(:monday),
      ends_at: 2.weeks.ago.end_of_week(:monday),
      status: "active"
    )
  end

  let!(:monthly_challenge) do
    Challenge.create!(
      title: "Monthly Bike 200km",
      description: "Bike 200km this month",
      challenge_type: "monthly",
      sport: "bike",
      target_value: 200,
      target_unit: "km",
      starts_at: 1.month.ago,
      ends_at: 1.month.ago.end_of_month,
      status: "active"
    )
  end

  let!(:participation) do
    ChallengeParticipation.create!(
      challenge: weekly_challenge,
      user: user,
      progress_value: 15,
      completed_at: 1.week.ago
    )
  end

  let!(:old_workout) do
    Workout.create!(
      user: user,
      challenge_participation: participation,
      sport: "run",
      distance_km: 15,
      duration_minutes: 90,
      workout_date: 10.days.ago.to_date
    )
  end

  let!(:monthly_participation) do
    ChallengeParticipation.create!(
      challenge: monthly_challenge,
      user: user,
      progress_value: 50,
      completed_at: nil
    )
  end

  it "rolls weekly challenge dates to the current week" do
    described_class.new.perform

    weekly_challenge.reload
    expect(weekly_challenge.starts_at.to_date).to eq(Date.current.beginning_of_week(:monday))
    expect(weekly_challenge.ends_at.to_date).to eq(Date.current.end_of_week(:monday))
  end

  it "clears participation progress for weekly challenges" do
    described_class.new.perform

    participation.reload
    expect(participation.progress_value).to eq(0)
    expect(participation.completed_at).to be_nil
  end

  it "detaches workouts from the previous week" do
    described_class.new.perform

    old_workout.reload
    expect(old_workout.challenge_participation_id).to be_nil
  end

  it "does not touch non-weekly challenges or their participations" do
    original_starts_at = monthly_challenge.starts_at
    original_progress = monthly_participation.progress_value

    described_class.new.perform

    monthly_challenge.reload
    monthly_participation.reload
    expect(monthly_challenge.starts_at.to_i).to eq(original_starts_at.to_i)
    expect(monthly_participation.progress_value).to eq(original_progress)
  end

  it "skips inactive weekly challenges" do
    weekly_challenge.update!(status: "archived")
    original_starts_at = weekly_challenge.starts_at

    described_class.new.perform

    weekly_challenge.reload
    expect(weekly_challenge.starts_at.to_i).to eq(original_starts_at.to_i)
    expect(participation.reload.progress_value).to eq(15)
  end
end
