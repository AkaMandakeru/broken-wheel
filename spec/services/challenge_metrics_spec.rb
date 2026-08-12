# frozen_string_literal: true

require "rails_helper"

# The metric registry is what every season mechanic is built on, so each entry
# gets a direct test.
RSpec.describe ChallengeMetrics do
  let(:user) { build_user }
  let(:context) { metric_context(user, window: august) }

  def value(metric, options: {}, ctx: context)
    described_class.call(metric, options.any? ? ctx.rescope(options: options) : ctx)
  end

  describe "distance_km" do
    it "sums distance inside the window and ignores what falls outside" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 10)
      build_workout(user, date: Date.new(2026, 8, 6), km: 5.5)
      build_workout(user, date: Date.new(2026, 7, 30), km: 100)

      expect(value("distance_km")).to eq(15.5)
    end
  end

  describe "activity_count" do
    it "counts activities in the window" do
      2.times { |i| build_workout(user, date: Date.new(2026, 8, 5 + i)) }
      build_workout(user, date: Date.new(2026, 9, 1))

      expect(value("activity_count")).to eq(2)
    end
  end

  describe "active_days" do
    it "counts distinct days, not activities" do
      build_workout(user, date: Date.new(2026, 8, 5), hour: 7)
      build_workout(user, date: Date.new(2026, 8, 5), hour: 19)
      build_workout(user, date: Date.new(2026, 8, 6))

      expect(value("active_days")).to eq(2)
    end
  end

  describe "longest_activity_km" do
    it "reports the single longest activity" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 4)
      build_workout(user, date: Date.new(2026, 8, 6), km: 12)

      expect(value("longest_activity_km")).to eq(12.0)
    end

    it "is zero with no activities" do
      expect(value("longest_activity_km")).to eq(0.0)
    end
  end

  describe "activities_over_km" do
    it "counts only activities at or above the threshold" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 10)
      build_workout(user, date: Date.new(2026, 8, 6), km: 9.9)
      build_workout(user, date: Date.new(2026, 8, 7), km: 15)

      expect(value("activities_over_km", options: { km: 10 })).to eq(2)
    end
  end

  describe "consecutive_days" do
    it "finds the longest unbroken run of days" do
      [ 3, 4, 5, 8, 9 ].each { |day| build_workout(user, date: Date.new(2026, 8, day)) }

      expect(value("consecutive_days")).to eq(3)
    end

    it "is zero without activities" do
      expect(value("consecutive_days")).to eq(0)
    end
  end

  describe "weeks_with_activity" do
    it "counts distinct calendar weeks" do
      build_workout(user, date: Date.new(2026, 8, 3))
      build_workout(user, date: Date.new(2026, 8, 4))
      build_workout(user, date: Date.new(2026, 8, 12))

      expect(value("weeks_with_activity")).to eq(2)
    end
  end

  describe "elevation_gain_m and calories" do
    it "sums both across the window" do
      build_workout(user, date: Date.new(2026, 8, 5), elevation: 120.5, calories: 400)
      build_workout(user, date: Date.new(2026, 8, 6), elevation: 80.0, calories: 250)

      expect(value("elevation_gain_m")).to eq(200.5)
      expect(value("calories")).to eq(650)
    end
  end

  describe "start_before_hour" do
    it "counts activities started before the cutoff" do
      build_workout(user, date: Date.new(2026, 8, 5), hour: 5, minute: 15)
      build_workout(user, date: Date.new(2026, 8, 6), hour: 6, minute: 0)

      expect(value("start_before_hour", options: { hour: 5, minute: 30 })).to eq(1)
    end

    # Manual entries carry no clock; letting them count would hand out the
    # "Early Bird" secret to someone who logged a run at midnight by default.
    it "ignores activities with no trustworthy start time" do
      build_workout(user, date: Date.new(2026, 8, 5), hour: 4, known_time: false)

      expect(value("start_before_hour", options: { hour: 5, minute: 30 })).to eq(0)
    end
  end

  describe "start_after_hour" do
    it "counts activities at or after the cutoff" do
      build_workout(user, date: Date.new(2026, 8, 5), hour: 23, minute: 10)
      build_workout(user, date: Date.new(2026, 8, 6), hour: 22, minute: 59)

      expect(value("start_after_hour", options: { hour: 23 })).to eq(1)
    end
  end

  describe "beat_previous_day" do
    it "flags a day that beat the one before it" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 5)
      build_workout(user, date: Date.new(2026, 8, 6), km: 8)

      expect(value("beat_previous_day")).to eq(1)
    end

    it "does not flag a day with no preceding day to beat" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 5)

      expect(value("beat_previous_day")).to eq(0)
    end
  end

  describe "personal_record" do
    it "flags a distance beyond anything logged before the window" do
      build_workout(user, date: Date.new(2026, 7, 20), km: 10)
      build_workout(user, date: Date.new(2026, 8, 5), km: 12)

      expect(value("personal_record")).to eq(1)
    end

    it "does not flag a distance short of the prior best" do
      build_workout(user, date: Date.new(2026, 7, 20), km: 15)
      build_workout(user, date: Date.new(2026, 8, 5), km: 12)

      expect(value("personal_record")).to eq(0)
    end

    # A first-ever workout beats nothing; awarding "Courage" for it would make
    # the mission meaningless for new users.
    it "does not flag a first-ever workout" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 12)

      expect(value("personal_record")).to eq(0)
    end
  end

  describe "fastest_5k_seconds" do
    it "projects the best 5 km time from qualifying activities" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 10, minutes: 50) # 300 s/km
      build_workout(user, date: Date.new(2026, 8, 6), km: 6, minutes: 27)  # 270 s/km

      expect(value("fastest_5k_seconds")).to eq(1350)
    end

    it "ignores activities shorter than 5 km" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 3, minutes: 12)

      expect(value("fastest_5k_seconds")).to be_nil
    end

    it "compares with :lte because lower is better" do
      expect(described_class.comparator_for("fastest_5k_seconds")).to eq(:lte)
      expect(described_class.satisfied?("fastest_5k_seconds", 1200, 1500)).to be(true)
      expect(described_class.satisfied?("fastest_5k_seconds", 1800, 1500)).to be(false)
    end

    it "treats a missing time as unsatisfied rather than as zero" do
      expect(described_class.satisfied?("fastest_5k_seconds", nil, 1500)).to be(false)
    end
  end

  describe "uninterrupted_activity" do
    it "counts activities whose elapsed time tracked their moving time" do
      build_workout(user, date: Date.new(2026, 8, 5), minutes: 30, elapsed: 1800)
      build_workout(user, date: Date.new(2026, 8, 6), minutes: 30, elapsed: 3600)

      expect(value("uninterrupted_activity")).to eq(1)
    end

    it "honours a minimum distance" do
      build_workout(user, date: Date.new(2026, 8, 5), km: 3, minutes: 30, elapsed: 1800)

      expect(value("uninterrupted_activity", options: { min_km: 5 })).to eq(0)
    end
  end

  describe "new_route" do
    it "counts routes never run before the window" do
      build_workout(user, date: Date.new(2026, 7, 20), route: "aaa")
      build_workout(user, date: Date.new(2026, 8, 5), route: "aaa")
      build_workout(user, date: Date.new(2026, 8, 6), route: "bbb")
      build_workout(user, date: Date.new(2026, 8, 7), route: "bbb")

      expect(value("new_route")).to eq(1)
    end

    it "ignores activities with no GPS track" do
      build_workout(user, date: Date.new(2026, 8, 5), route: nil)

      expect(value("new_route")).to eq(0)
    end
  end

  describe "club metrics" do
    it "reports club membership and club-era workouts" do
      expect(value("club_member")).to eq(0)

      club = Club.create!(name: "Runners", sport: "run", created_by: user)
      ClubMembership.create!(user: user, club: club, role: "member")
      build_workout(user, date: Date.new(2026, 8, 5))

      fresh = metric_context(user, window: august)
      expect(described_class.call("club_member", fresh)).to eq(1)
      expect(described_class.call("club_workout_count", fresh)).to eq(1)
    end
  end

  describe "battle_pass_level" do
    it "reads the participation level" do
      season = build_season
      participation = SeasonProgressService.ensure_participation(user, season)
      participation.update!(level: 12)

      ctx = metric_context(user, window: august, season: season, participation: participation)
      expect(described_class.call("battle_pass_level", ctx)).to eq(12)
    end
  end

  describe "registry integrity" do
    it "resolves every registered metric against an empty history" do
      season = build_season
      participation = SeasonProgressService.ensure_participation(user, season)
      ctx = metric_context(user, window: august, season: season, participation: participation)

      described_class.keys.each do |key|
        expect { described_class.call(key, ctx) }.not_to raise_error, "metric #{key} raised"
      end
    end

    it "raises a clear error for an unknown metric" do
      expect { described_class.call("nope", context) }.to raise_error(described_class::UnknownMetric, /nope/)
    end
  end
end
