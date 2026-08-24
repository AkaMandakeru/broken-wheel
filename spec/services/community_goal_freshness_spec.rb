# frozen_string_literal: true

require "rails_helper"

# Two things went wrong for a player who imported a workout: the community bar
# didn't move, and it had also gone *backwards* since they last looked.
RSpec.describe "Community goal freshness" do
  let(:user) { build_user }
  let(:season) { build_season }
  let!(:participation) { SeasonProgressService.ensure_participation(user, season) }

  let!(:goal) do
    season.season_community_goals.create!(
      key: "marathon", metric: "distance_km",
      target_mode: "per_participant", per_participant: 60,
      target_value: 60, base_target_value: 60
    )
  end

  describe "when a workout is imported" do
    # It used to update only from a cron that runs in production alone, so in
    # development the bar sat frozen no matter how far anyone ran.
    it "refreshes as part of the season recalculation" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 30)

      expect { SeasonProgressService.new(participation).recalculate }
        .to change { goal.reload.current_value.to_f }.from(0).to(30.0)
    end

    it "stamps when it was computed" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 10)
      SeasonProgressService.new(participation).recalculate

      expect(goal.reload.computed_at).to be_within(1.minute).of(Time.current)
    end

    # One aggregate query per goal is cheap, but a 40-activity import shouldn't
    # run it forty times.
    it "skips a refresh that just happened" do
      SeasonProgressService.new(participation).recalculate
      first = goal.reload.computed_at

      SeasonProgressService.new(participation).recalculate

      expect(goal.reload.computed_at).to eq(first)
    end

    it "never fails the recalculation if aggregation breaks" do
      allow(Seasons::CommunityAggregator).to receive(:refresh_season).and_raise(ActiveRecord::StatementInvalid)

      expect { SeasonProgressService.new(participation).recalculate }.not_to raise_error
    end
  end

  describe "when someone new joins" do
    before do
      build_workout(user, date: Date.new(2026, 8, 5), km: 30)
      SeasonProgressService.new(participation).recalculate
    end

    # This is what read as "it was blanked out": the target was recomputed from
    # the live participant count, so a new member pushed everyone's bar down.
    it "does not move the target of the tier already in flight" do
      before_target = goal.reload.effective_target
      before_percent = goal.percent_complete

      3.times { SeasonProgressService.ensure_participation(build_user, season) }

      expect(goal.reload.effective_target).to eq(before_target)
      expect(goal.percent_complete).to eq(before_percent)
    end

    it "sizes the next tier to the larger community" do
      3.times { SeasonProgressService.ensure_participation(build_user, season) }
      goal.update!(tier: 2, tier_started_value: goal.effective_target)
      goal.freeze_tier_target!

      # 4 participants × 60 = 240 base, doubled for tier 2.
      expect(goal.reload.effective_target).to eq(480.0)
    end
  end

  describe "a fixed-target goal" do
    it "is unaffected by the participant count" do
      fixed = season.season_community_goals.create!(
        key: "fixed_one", metric: "distance_km", target_mode: "fixed",
        target_value: 500, base_target_value: 500
      )

      5.times { SeasonProgressService.ensure_participation(build_user, season) }

      expect(fixed.reload.effective_target).to eq(500.0)
    end
  end
end
