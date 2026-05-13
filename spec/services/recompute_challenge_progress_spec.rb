# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecomputeChallengeProgress do
  let(:user) do
    User.create!(
      first_name: "Recomp",
      last_name: "Tester",
      email: "recomp-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  let(:km_challenge) do
    Challenge.create!(
      title: "Run 20km",
      description: "Run 20km",
      challenge_type: "weekly",
      sport: "run",
      target_value: 20,
      target_unit: "km",
      starts_at: Date.current.beginning_of_week(:monday),
      ends_at: Date.current.end_of_week(:monday),
      status: "active"
    )
  end

  let(:hours_challenge) do
    Challenge.create!(
      title: "Bike 5 hours",
      description: "Bike 5 hours",
      challenge_type: "weekly",
      sport: "bike",
      target_value: 5,
      target_unit: "hours",
      starts_at: Date.current.beginning_of_week(:monday),
      ends_at: Date.current.end_of_week(:monday),
      status: "active"
    )
  end

  def participation_for(challenge)
    ChallengeParticipation.create!(challenge: challenge, user: user, progress_value: 0, completed_at: nil)
  end

  def add_workout(participation, distance_km: 0, duration_minutes: 0)
    Workout.create!(
      user: user,
      challenge_participation: participation,
      sport: participation.challenge.sport,
      distance_km: distance_km,
      duration_minutes: duration_minutes,
      workout_date: Date.current
    )
  end

  describe "#call" do
    context "when target_unit is km" do
      it "sums distance_km from the participation's workouts" do
        participation = participation_for(km_challenge)
        add_workout(participation, distance_km: 7)
        add_workout(participation, distance_km: 5)

        described_class.new(participation).call

        expect(participation.reload.progress_value).to eq(12)
      end

      it "leaves completed_at nil when progress is below target" do
        participation = participation_for(km_challenge)
        add_workout(participation, distance_km: 5)

        described_class.new(participation).call

        expect(participation.reload.completed_at).to be_nil
      end

      it "marks the participation completed and awards a badge when progress reaches target" do
        participation = participation_for(km_challenge)
        add_workout(participation, distance_km: 20)

        expect {
          described_class.new(participation).call
        }.to change { user.user_badges.count }.by(1)

        expect(participation.reload.completed_at).to be_present
        badge = user.user_badges.last.badge
        expect(badge.name).to eq("Completed: Run 20km")
        expect(badge.badge_type).to eq("challenge_completion")
      end
    end

    context "when target_unit is not km" do
      it "converts duration_minutes to hours" do
        participation = participation_for(hours_challenge)
        add_workout(participation, duration_minutes: 90)
        add_workout(participation, duration_minutes: 60)

        described_class.new(participation).call

        expect(participation.reload.progress_value).to eq(2.5)
      end
    end

    context "idempotency" do
      it "does not award a second badge when called again on a completed participation" do
        participation = participation_for(km_challenge)
        add_workout(participation, distance_km: 25)
        described_class.new(participation).call

        expect {
          described_class.new(participation.reload).call
        }.not_to change { user.user_badges.count }
      end

      it "does not move completed_at on subsequent calls" do
        participation = participation_for(km_challenge)
        add_workout(participation, distance_km: 25)
        described_class.new(participation).call
        first_completed_at = participation.reload.completed_at

        add_workout(participation, distance_km: 5)
        described_class.new(participation.reload).call

        expect(participation.reload.completed_at).to eq(first_completed_at)
      end
    end
  end
end
