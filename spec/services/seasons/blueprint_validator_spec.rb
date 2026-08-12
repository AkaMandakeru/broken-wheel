# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seasons::BlueprintValidator do
  def base(overrides = {})
    {
      "key" => "test_season", "name" => "Test", "starts_at" => "2026-09-01", "ends_at" => "2026-09-30",
      "max_level" => 10
    }.merge(overrides)
  end

  def errors_for(data)
    described_class.call(data).errors
  end

  it "accepts a minimal blueprint" do
    expect(described_class.call(base)).to be_valid
  end

  it "accepts the shipped template" do
    data = YAML.safe_load_file(Rails.root.join("db/seeds/seasons/TEMPLATE.yml"), permitted_classes: [ Date, Time ])
    validator = described_class.call(data)

    expect(validator.errors).to be_empty
  end

  it "accepts the reference season" do
    data = YAML.safe_load_file(Rails.root.join("db/seeds/seasons/season_8_legacy_of_champions.yml"), permitted_classes: [ Date, Time ])
    validator = described_class.call(data)

    expect(validator.errors).to be_empty
    expect(validator.warnings).to be_empty
  end

  it "reports every missing required field at once" do
    errors = errors_for({})

    expect(errors).to include(/key: is required/, /name: is required/, /starts_at: is required/, /ends_at: is required/)
  end

  it "rejects a non-mapping document" do
    expect(errors_for([ "not", "a", "mapping" ])).to include(/must be a YAML mapping/)
  end

  it "rejects a key that is not a slug" do
    expect(errors_for(base("key" => "My Season!"))).to include(/key: must be lowercase/)
  end

  it "rejects an end date before the start" do
    expect(errors_for(base("ends_at" => "2026-08-01"))).to include(/ends_at: must be after starts_at/)
  end

  it "rejects an unknown theme, status and timezone" do
    errors = errors_for(base("theme" => "neon", "status" => "paused", "time_zone" => "Mars/Olympus"))

    expect(errors).to include(/theme: "neon" is not a theme/, /status: "paused" is not a status/, /time_zone: .* not a known timezone/)
  end

  it "rejects a level count outside the supported range" do
    expect(errors_for(base("max_level" => 0))).to include(/max_level: must be between 1 and 100/)
    expect(errors_for(base("max_level" => 500))).to include(/max_level: must be between 1 and 100/)
  end

  describe "challenges" do
    def with_challenge(entry)
      base("challenges" => [ entry ])
    end

    it "names an unknown metric and suggests a close one" do
      errors = errors_for(with_challenge("key" => "c", "requirements" => [ { "metric" => "distance_kms", "target" => 5 } ]))

      expect(errors.first).to match(/is not a known metric/)
      expect(errors.first).to match(/Did you mean "distance_km"/)
    end

    it "requires at least one requirement" do
      expect(errors_for(with_challenge("key" => "c"))).to include(/requirements: at least one requirement is required/)
    end

    it "rejects a non-positive target" do
      errors = errors_for(with_challenge("key" => "c", "requirements" => [ { "metric" => "distance_km", "target" => 0 } ]))

      expect(errors).to include(/target: must be greater than 0/)
    end

    it "rejects duplicate challenge keys" do
      data = base("challenges" => [
        { "key" => "same", "requirements" => [ { "metric" => "distance_km", "target" => 5 } ] },
        { "key" => "same", "requirements" => [ { "metric" => "distance_km", "target" => 5 } ] }
      ])

      expect(errors_for(data)).to include(/key "same" is already used/)
    end

    # The usual cause is dates copied from the season the challenge came from.
    it "rejects a window outside the season" do
      errors = errors_for(with_challenge(
        "key" => "c", "starts_at" => "2026-08-01", "ends_at" => "2026-08-07",
        "requirements" => [ { "metric" => "distance_km", "target" => 5 } ]
      ))

      expect(errors).to include(/starts_at: .* is outside the season/)
    end

    it "rejects an unlock level above the season's ceiling" do
      errors = errors_for(with_challenge(
        "key" => "c", "unlock_level" => 25,
        "requirements" => [ { "metric" => "distance_km", "target" => 5 } ]
      ))

      expect(errors).to include(/unlock_level: is 25 but the season only has 10 levels/)
    end

    it "rejects an unknown category" do
      errors = errors_for(with_challenge("key" => "c", "category" => "epic",
                                         "requirements" => [ { "metric" => "distance_km", "target" => 5 } ]))

      expect(errors).to include(/category: "epic" is not a category/)
    end
  end

  describe "rewards" do
    def with_reward(entry)
      base("rewards" => [ entry ])
    end

    it "rejects an unknown reward type" do
      errors = errors_for(with_reward("reward_key" => "x", "reward_type" => "sticker", "level" => 1))

      expect(errors).to include(/reward_type: "sticker" is not valid/)
    end

    it "rejects a level above the season's ceiling" do
      errors = errors_for(with_reward("reward_key" => "x", "reward_type" => "badge", "level" => 30))

      expect(errors).to include(/level: is 30 but the season only has 10 levels/)
    end

    it "requires a level for a level reward" do
      expect(errors_for(with_reward("reward_key" => "x", "reward_type" => "badge")))
        .to include(/level: is required for a level reward/)
    end

    it "requires an unlock_value for a non-level reward" do
      errors = errors_for(with_reward("reward_key" => "x", "reward_type" => "badge", "unlock_kind" => "legacy"))

      expect(errors).to include(/unlock_value: is required for a legacy reward/)
    end

    it "requires coins on a coins reward" do
      errors = errors_for(with_reward("reward_key" => "x", "reward_type" => "coins", "level" => 1))

      expect(errors).to include(/coins: must be greater than 0/)
    end

    # A cosmetic reward pointing at nothing silently grants nothing.
    it "rejects a cosmetic that is neither defined nor already present" do
      errors = errors_for(with_reward("reward_key" => "ghost_frame", "reward_type" => "cosmetic", "level" => 1))

      expect(errors).to include(/cosmetic "ghost_frame" is not defined/)
    end

    it "accepts a cosmetic defined in the same blueprint" do
      data = base(
        "cosmetics" => [ { "key" => "new_frame", "kind" => "frame" } ],
        "rewards" => [ { "reward_key" => "new_frame", "reward_type" => "cosmetic", "level" => 1 } ]
      )

      expect(described_class.call(data)).to be_valid
    end

    # A title missing from config/titles.yml is silently refused by
    # User#add_title, so the reward would appear to grant and do nothing.
    it "warns about a title that is not in the catalogue" do
      validator = described_class.call(with_reward("reward_key" => "nonexistent", "reward_type" => "title", "level" => 1))

      expect(validator).to be_valid
      expect(validator.warnings).to include(/title "nonexistent" is not in config\/titles.yml/)
    end
  end

  describe "community goal" do
    it "rejects a metric that cannot be summed across people" do
      data = base("community_goal" => { "key" => "g", "metric" => "consecutive_days", "target_value" => 10 })

      expect(errors_for(data)).to include(/cannot be summed across a community/)
    end

    it "requires per_participant when the mode needs it" do
      data = base("community_goal" => { "key" => "g", "metric" => "distance_km", "target_mode" => "per_participant" })

      expect(errors_for(data)).to include(/per_participant: must be greater than 0/)
    end

    it "rejects a milestone percent outside 1..100" do
      data = base("community_goal" => {
        "key" => "g", "metric" => "distance_km", "target_value" => 100,
        "milestones" => [ { "percent" => 150 } ]
      })

      expect(errors_for(data)).to include(/percent must be between 1 and 100/)
    end
  end

  describe "daily templates" do
    it "warns when the pool is too small to vary" do
      data = base("daily_templates" => [ { "key" => "a", "metric" => "distance_km", "target" => 3 } ])
      validator = described_class.call(data)

      expect(validator).to be_valid
      expect(validator.warnings).to include(/three are drawn per day/)
    end

    it "rejects duplicate keys" do
      data = base("daily_templates" => [
        { "key" => "dup", "metric" => "distance_km", "target" => 3 },
        { "key" => "dup", "metric" => "distance_km", "target" => 5 }
      ])

      expect(errors_for(data)).to include(/key "dup" is already used/)
    end
  end

  it "summarises what would be created" do
    data = base(
      "challenges" => [ { "key" => "c", "requirements" => [ { "metric" => "distance_km", "target" => 5 } ] } ],
      "daily_templates" => [ { "key" => "d", "metric" => "distance_km", "target" => 3 } ]
    )

    expect(described_class.call(data).summary).to include(challenges: 1, daily_templates: 1)
  end
end
