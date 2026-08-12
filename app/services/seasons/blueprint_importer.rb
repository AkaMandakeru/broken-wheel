# frozen_string_literal: true

module Seasons
  # Builds a whole season from one YAML blueprint: challenges and their
  # requirements, battle pass rewards, legacy missions, daily templates,
  # cosmetics and the community goal.
  #
  # Every record is upserted by key and nothing is ever deleted, so running the
  # import twice is a no-op and re-running it after editing the blueprint
  # updates in place without touching player progress.
  class BlueprintImporter
    class MissingBlueprint < StandardError; end
    class InvalidBlueprint < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = Array(errors)
        super(@errors.join("; "))
      end
    end

    BLUEPRINT_DIR = Rails.root.join("db/seeds/seasons")

    # Files that are documentation rather than importable seasons.
    TEMPLATE_KEY = "TEMPLATE"

    # Imports a blueprint shipped in db/seeds/seasons.
    def self.call(key)
      new(load_file(key)).call
    end

    # Imports YAML pasted or uploaded through the admin panel.
    def self.from_yaml(content)
      new(parse(content)).call
    end

    def self.validate_yaml(content)
      BlueprintValidator.call(parse(content))
    rescue Psych::SyntaxError => e
      BlueprintValidator.new(nil).tap { |v| v.errors << "YAML syntax error on line #{e.line}: #{e.problem}" }
    end

    # Blueprints available to import from disk, newest season first.
    def self.available
      Dir.glob(BLUEPRINT_DIR.join("*.yml")).filter_map do |path|
        key = File.basename(path, ".yml")
        next if key == TEMPLATE_KEY

        data = YAML.safe_load_file(path, permitted_classes: [ Date, Time ], aliases: true)
        next unless data.is_a?(Hash)

        { key: key, name: data["name"], starts_at: data["starts_at"], ends_at: data["ends_at"],
          imported: Season.exists?(key: data["key"]) }
      rescue Psych::SyntaxError
        next
      end.sort_by { |b| b[:starts_at].to_s }.reverse
    end

    def self.template_path
      BLUEPRINT_DIR.join("#{TEMPLATE_KEY}.yml")
    end

    def self.load_file(key)
      path = BLUEPRINT_DIR.join("#{key}.yml")
      raise MissingBlueprint, "No blueprint at #{path}" unless path.exist?

      YAML.safe_load_file(path, permitted_classes: [ Date, Time ], aliases: true)
    end

    def self.parse(content)
      YAML.safe_load(content.to_s, permitted_classes: [ Date, Time ], aliases: true)
    end

    private_class_method :load_file, :parse

    def initialize(data)
      @data = data
    end

    # Validated up front and wrapped in a transaction: an import writes across
    # nine tables, and a failure halfway would otherwise leave a half-built
    # season behind for someone to unpick by hand.
    def call
      validation = BlueprintValidator.call(@data)
      raise InvalidBlueprint, validation.errors unless validation.valid?

      season = nil
      ApplicationRecord.transaction do
        season = upsert_season
        import_cosmetics
        import_challenges(season)
        import_rewards(season)
        import_legacy_missions(season)
        import_daily_templates(season)
        import_community_goal(season)
      end
      season.reload
    end

    private

    def upsert_season
      season = Season.find_or_initialize_by(key: @data.fetch("key"))
      season.assign_attributes(
        name: @data.fetch("name"),
        slogan: @data["slogan"],
        description: @data["description"],
        theme: @data.fetch("theme", "default"),
        status: @data.fetch("status", "active"),
        starts_at: @data["starts_at"],
        ends_at: @data["ends_at"],
        time_zone: @data.fetch("time_zone", "America/Sao_Paulo"),
        xp_multiplier: @data.fetch("xp_multiplier", 1.0),
        max_level: max_level,
        top_level_xp: top_level_xp,
        curve_exponent: @data.fetch("curve_exponent", LevelCurve::DEFAULT_EXPONENT)
      )
      # An explicit curve overrides the derived one; otherwise Season rebuilds it
      # from max_level / top_level_xp on save.
      season.level_curve = explicit_curve if explicit_curve
      season.save!
      season
    end

    def max_level
      @data.fetch("max_level", 10).to_i
    end

    def top_level_xp
      @data.fetch("top_level_xp", LevelCurve::DEFAULT_TOP_LEVEL_XP).to_i
    end

    def explicit_curve
      curve = @data["level_curve"]
      curve.present? ? curve.map(&:to_i) : nil
    end

    # --- Challenges -----------------------------------------------------------

    def import_challenges(season)
      Array(@data["challenges"]).each_with_index do |entry, index|
        challenge = upsert_challenge(season, entry)
        upsert_requirements(challenge, entry)
        upsert_season_challenge(season, challenge, entry, index)
      end
    end

    def upsert_challenge(season, entry)
      challenge = Challenge.find_or_initialize_by(key: entry.fetch("key"))
      challenge.assign_attributes(
        title: entry["title"].presence || entry.fetch("key").humanize,
        description: entry["description"],
        # Season content is `custom` with fixed dates on purpose: a `weekly`
        # challenge would be rolled forward and wiped by ResetWeeklyChallengesJob.
        challenge_type: entry.fetch("challenge_type", "custom"),
        sport: entry["sport"],
        status: entry.fetch("status", "active"),
        starts_at: entry["starts_at"] || season.starts_at,
        ends_at: entry["ends_at"] || season.ends_at,
        target_value: primary_target(entry),
        target_unit: primary_unit(entry)
      )
      challenge.save!
      challenge
    end

    # The legacy single-target columns stay in sync with the first requirement
    # so older views and admin screens keep working.
    def primary_target(entry)
      Array(entry["requirements"]).first&.fetch("target", nil)
    end

    def primary_unit(entry)
      metric = Array(entry["requirements"]).first&.fetch("metric", nil)
      return nil if metric.blank?

      case ChallengeMetrics.unit_for(metric)
      when "km" then "km"
      when "hours" then "hours"
      else "times"
      end
    end

    def upsert_requirements(challenge, entry)
      requirements = Array(entry["requirements"])
      requirements.each_with_index do |requirement, position|
        record = challenge.challenge_requirements.find_or_initialize_by(
          metric: requirement.fetch("metric"), position: position
        )
        record.assign_attributes(
          target: requirement.fetch("target"),
          comparator: requirement["comparator"] || ChallengeMetrics.comparator_for(requirement.fetch("metric")).to_s,
          options: requirement["options"] || {},
          unit: requirement["unit"],
          label_key: requirement["label_key"]
        )
        record.save!
      end

      # Requirements removed from the blueprint should disappear from the challenge.
      challenge.challenge_requirements.where(position: requirements.size..).destroy_all
    end

    def upsert_season_challenge(season, challenge, entry, index)
      season_challenge = season.season_challenges.find_or_initialize_by(challenge: challenge)
      season_challenge.assign_attributes(
        position: entry.fetch("position", index),
        category: entry.fetch("category", "standard"),
        xp_reward: entry.fetch("xp_reward", 0),
        coin_reward: entry.fetch("coin_reward", 0),
        fragment_reward: entry.fetch("fragment_reward", 0),
        unlock_level: entry.fetch("unlock_level", 0),
        hidden: entry.fetch("hidden", false),
        required: entry.fetch("required", false),
        week_index: entry["week_index"],
        # The window belongs to the season, not the challenge — so the same
        # challenge reused next month is scored over next month.
        starts_at: entry["starts_at"],
        ends_at: entry["ends_at"]
      )
      season_challenge.save!
      season_challenge
    end

    # --- Rewards --------------------------------------------------------------

    def import_rewards(season)
      Array(@data["rewards"]).each_with_index do |entry, index|
        unlock_kind = entry.fetch("unlock_kind", "level")
        reward = season.season_rewards.find_or_initialize_by(
          reward_key: entry.fetch("reward_key"),
          unlock_kind: unlock_kind,
          track: entry.fetch("track", "free")
        )
        reward.assign_attributes(
          reward_type: entry.fetch("reward_type"),
          name: entry["name"],
          level: entry["level"],
          unlock_value: entry["unlock_value"] || entry["level"],
          coins: entry.fetch("coins", 0),
          position: entry.fetch("position", index),
          payload: entry["payload"] || {}
        )
        reward.save!
      end
    end

    # --- Legacy missions ------------------------------------------------------

    def import_legacy_missions(season)
      Array(@data["legacy_missions"]).each_with_index do |entry, index|
        objective = season.season_objectives.find_or_initialize_by(
          track: "legacy", name: entry.fetch("key")
        )
        objective.assign_attributes(
          kind: "legacy",
          metric: entry.fetch("metric"),
          target: entry.fetch("target"),
          options: entry["options"] || {},
          xp_reward: entry.fetch("xp_reward", 0),
          coin_reward: entry.fetch("coin_reward", 0),
          fragment_reward: entry.fetch("fragment_reward", 0),
          icon: entry["icon"],
          position: entry.fetch("position", index),
          required: false
        )
        objective.save!
      end
    end

    # --- Daily templates ------------------------------------------------------

    def import_daily_templates(season)
      Array(@data["daily_templates"]).each do |entry|
        template = DailyChallengeTemplate.find_or_initialize_by(season: season, key: entry.fetch("key"))
        template.assign_attributes(
          metric: entry.fetch("metric"),
          target: entry.fetch("target"),
          options: entry["options"] || {},
          sport: entry["sport"],
          xp_reward: entry.fetch("xp_reward", 50),
          coin_reward: entry.fetch("coin_reward", 25),
          weight: entry.fetch("weight", 1),
          active: entry.fetch("active", true),
          requires_start_time: entry.fetch("requires_start_time", false)
        )
        template.save!
      end
    end

    # --- Cosmetics ------------------------------------------------------------

    def import_cosmetics
      Array(@data["cosmetics"]).each do |entry|
        cosmetic = Cosmetic.find_or_initialize_by(key: entry.fetch("key"))
        kind = entry.fetch("kind")
        cosmetic.assign_attributes(
          kind: kind,
          name: entry["name"],
          rarity: entry.fetch("rarity", "common"),
          css_class: entry["css_class"],
          icon: entry["icon"],
          animated: entry.fetch("animated", false),
          # Items we can't draw yet are still collectible; they simply stay
          # unequippable until their art exists.
          renderable: entry.fetch("renderable", Cosmetic::RENDERABLE_KINDS.include?(kind))
        )
        cosmetic.save!
      end
    end

    # --- Community goal -------------------------------------------------------

    def import_community_goal(season)
      entry = @data["community_goal"]
      return if entry.blank?

      goal = season.season_community_goals.find_or_initialize_by(key: entry.fetch("key"))
      base = entry.fetch("target_value", entry["per_participant"] || 1)
      goal.assign_attributes(
        metric: entry.fetch("metric"),
        target_mode: entry.fetch("target_mode", "fixed"),
        per_participant: entry["per_participant"],
        target_value: base,
        base_target_value: base,
        tier_coin_reward: entry.fetch("tier_coin_reward", 0),
        max_tiers: entry["max_tiers"]
      )
      goal.save!

      # Only tier 1 is seeded — later tiers are created as each one is cleared,
      # so a re-import never disturbs a community mid-climb.
      Array(entry["milestones"]).each do |milestone_entry|
        percent = milestone_entry.is_a?(Hash) ? milestone_entry.fetch("percent") : milestone_entry
        reward_key = milestone_entry.is_a?(Hash) ? milestone_entry["reward_key"] : nil

        milestone = goal.season_community_milestones.find_or_initialize_by(tier: 1, percent: percent)
        milestone.assign_attributes(
          threshold: goal.base_target * (percent.to_f / 100),
          season_reward: reward_key && season.season_rewards.find_by(reward_key: reward_key, unlock_kind: "community")
        )
        milestone.save!
      end
    end
  end
end
