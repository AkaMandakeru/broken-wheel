# frozen_string_literal: true

require "rails_helper"

# Exporting is how next month gets built, so the guarantee that matters is the
# round trip: an exported season must import back into the same season.
RSpec.describe Seasons::BlueprintExporter do
  let!(:season) { Seasons::BlueprintImporter.call("season_8_legacy_of_champions") }

  def exported(**options)
    YAML.safe_load(described_class.call(season, **options), permitted_classes: [ Date, Time ])
  end

  it "exports valid YAML" do
    expect { exported }.not_to raise_error
  end

  it "produces a blueprint the validator accepts" do
    validator = Seasons::BlueprintValidator.call(exported)

    expect(validator.errors).to be_empty
  end

  it "carries every part of the season across" do
    data = exported

    expect(data["challenges"].size).to eq(season.season_challenges.count)
    expect(data["rewards"].size).to eq(season.season_rewards.count)
    expect(data["legacy_missions"].size).to eq(season.season_objectives.legacy.count)
    expect(data["daily_templates"].size).to eq(DailyChallengeTemplate.where(season: season).count)
    expect(data["community_goal"]["key"]).to eq(season.season_community_goals.first.key)
    expect(data["max_level"]).to eq(season.max_level)
  end

  it "preserves compound requirements" do
    week1 = exported["challenges"].find { |c| c["key"] == "s8_week1_beginning" }

    expect(week1["requirements"].map { |r| r["metric"] })
      .to eq(%w[distance_km activity_count longest_activity_km])
    expect(week1["requirements"].map { |r| r["target"] }).to eq([ 15, 4, 6 ])
  end

  # Reusing the key would edit the season being exported instead of making a new one.
  it "defaults to a distinct key and an inactive status" do
    data = exported

    expect(data["key"]).not_to eq(season.key)
    expect(data["status"]).to eq("upcoming")
  end

  it "takes a new key and name" do
    data = exported(key: "september_2026", name: "September Grind")

    expect(data["key"]).to eq("september_2026")
    expect(data["name"]).to eq("September Grind")
  end

  describe "shifting to a new month" do
    let(:data) { exported(shift_to: Date.new(2026, 9, 1)) }

    it "moves the season window" do
      expect(data["starts_at"]).to eq("2026-09-01")
      expect(data["ends_at"]).to eq("2026-10-01")
    end

    # Every date moves by the same offset, so a week-3 challenge stays in week 3.
    it "moves challenge windows by the same offset" do
      week1 = data["challenges"].find { |c| c["key"] == "s8_week1_beginning" }
      week3 = data["challenges"].find { |c| c["key"] == "s8_week3_endurance" }

      expect(week1["starts_at"]).to eq("2026-09-01")
      expect(week1["ends_at"]).to eq("2026-09-07")
      expect(week3["starts_at"]).to eq("2026-09-15")
    end

    it "keeps challenge windows inside the shifted season" do
      expect(Seasons::BlueprintValidator.call(data).errors).to be_empty
    end
  end

  describe "round trip" do
    it "imports back into an equivalent season" do
      yaml = described_class.call(season, key: "round_trip", name: "Round Trip")
      copy = Seasons::BlueprintImporter.from_yaml(yaml)

      expect(copy.key).to eq("round_trip")
      expect(copy.max_level).to eq(season.max_level)
      expect(copy.level_curve).to eq(season.level_curve)
      expect(copy.season_challenges.count).to eq(season.season_challenges.count)
      expect(copy.season_rewards.count).to eq(season.season_rewards.count)
      expect(copy.season_objectives.legacy.count).to eq(season.season_objectives.legacy.count)
      expect(copy.season_community_goals.count).to eq(1)
    end

    it "leaves the original season untouched" do
      before = season.season_challenges.count
      Seasons::BlueprintImporter.from_yaml(described_class.call(season, key: "round_trip_2"))

      expect(season.reload.season_challenges.count).to eq(before)
      expect(Season.where(key: season.key).count).to eq(1)
    end

    # The two seasons share challenge definitions, so this is the reuse case
    # that used to carry progress over.
    it "gives a player separate progress in the copy" do
      user = build_user
      copy = Seasons::BlueprintImporter.from_yaml(
        described_class.call(season, key: "round_trip_3", shift_to: Date.new(2026, 9, 1))
      )
      copy.update!(status: "active")

      4.times { |i| build_workout(user, date: Date.new(2026, 8, 2 + i), km: 10) }
      SeasonProgressService.ensure_participation(user, season)
      SeasonProgressService.ensure_participation(user, copy)
      user.challenge_participations.each { |cp| RecomputeChallengeProgress.new(cp).call }

      august = user.challenge_participations.find_by(season: season, challenge: Challenge.find_by(key: "s8_week1_beginning"))
      september = user.challenge_participations.find_by(season: copy, challenge: Challenge.find_by(key: "s8_week1_beginning"))

      expect(august.progress_value.to_f).to be > 0
      expect(september.progress_value.to_f).to eq(0.0)
    end
  end
end
