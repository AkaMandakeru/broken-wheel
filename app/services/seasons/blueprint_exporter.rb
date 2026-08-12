# frozen_string_literal: true

module Seasons
  # Dumps an existing season back to a blueprint.
  #
  # This is how next month gets built: export the season that worked, change the
  # key and the dates, adjust what you want, import it back. Round-tripping an
  # export through the importer reproduces the same season, so an exported file
  # is always a valid starting point.
  class BlueprintExporter
    def self.call(season, **options)
      new(season, **options).to_yaml
    end

    # `shift_to` rewrites every date onto a new month, which is the whole point
    # of exporting: the content is reusable, the calendar never is.
    def initialize(season, key: nil, name: nil, shift_to: nil)
      @season = season
      @key = key
      @name = name
      @shift_to = shift_to&.to_date
    end

    def to_yaml
      header + data.to_yaml.sub(/\A---\n/, "")
    end

    def data
      {
        "key" => @key.presence || "#{@season.key}_copy",
        "name" => @name.presence || @season.name,
        "slogan" => @season.slogan,
        "description" => @season.description,
        "theme" => @season.theme,
        "status" => "upcoming",
        "starts_at" => shift(@season.starts_at)&.to_s,
        "ends_at" => shift(@season.ends_at)&.to_s,
        "time_zone" => @season.time_zone,
        "xp_multiplier" => @season.xp_multiplier.to_f,
        "max_level" => @season.max_level,
        "top_level_xp" => @season.effective_top_level_xp,
        "curve_exponent" => @season.curve_exponent.to_f,
        "cosmetics" => cosmetics,
        "challenges" => challenges,
        "rewards" => rewards,
        "legacy_missions" => legacy_missions,
        "community_goal" => community_goal,
        "daily_templates" => daily_templates
      }.compact
    end

    private

    def header
      <<~YAML
        # Exported from "#{@season.name}" on #{Date.current}.
        #
        # To run this as a new season:
        #   1. Change `key` — it must be unique, and it is what the importer
        #      upserts on. Reusing a key edits that season instead of creating one.
        #   2. Check `starts_at` / `ends_at`.#{@shift_to ? " Dates were shifted by a fixed\n        #      offset, which keeps each challenge in its own week but preserves the\n        #      original length — trim `ends_at` if the new month is shorter." : ''}
        #   3. Set `status: active` when you want it live.
        #
        # Import at /admin/season_imports/new, or:
        #   rails 'seasons:import[<key>]'   (after saving to db/seeds/seasons/)

      YAML
    end

    # Offsets a date by the same number of days the season start moves, so a
    # week-3 challenge stays in week 3.
    def shift(time)
      return time&.to_date if @shift_to.nil? || @season.starts_at.nil?

      offset = (@shift_to - @season.starts_at.to_date).to_i
      time&.to_date&.+(offset)
    end

    def challenges
      @season.season_challenges.includes(challenge: :challenge_requirements).order(:position).map do |sc|
        challenge = sc.challenge
        {
          "key" => challenge.key.presence || "challenge_#{challenge.id}",
          "title" => challenge.title,
          "description" => challenge.description,
          "category" => sc.category,
          "sport" => challenge.sport,
          "challenge_type" => challenge.challenge_type,
          "week_index" => sc.week_index,
          "position" => sc.position,
          "xp_reward" => sc.xp_reward,
          "coin_reward" => sc.coin_reward,
          "fragment_reward" => sc.fragment_reward,
          "unlock_level" => sc.unlock_level.positive? ? sc.unlock_level : nil,
          "hidden" => (sc.hidden? || nil),
          "required" => (sc.required? || nil),
          "starts_at" => shift(sc.starts_at)&.to_s,
          "ends_at" => shift(sc.ends_at)&.to_s,
          "requirements" => challenge.challenge_requirements.ordered.map { |r| requirement(r) }
        }.compact
      end
    end

    def requirement(record)
      {
        "metric" => record.metric,
        "target" => numeric(record.target),
        "comparator" => (record.comparator == "gte" ? nil : record.comparator),
        "options" => record.options.presence
      }.compact
    end

    def rewards
      @season.season_rewards.order(:unlock_kind, :level, :position).map do |reward|
        {
          "level" => reward.level,
          "unlock_kind" => (reward.unlock_kind == "level" ? nil : reward.unlock_kind),
          "unlock_value" => (reward.unlock_kind == "level" ? nil : reward.unlock_value),
          "track" => reward.track,
          "reward_type" => reward.reward_type,
          "reward_key" => reward.reward_key,
          "name" => reward.name,
          "coins" => (reward.coins.positive? ? reward.coins : nil),
          "payload" => reward.payload.presence
        }.compact
      end
    end

    def legacy_missions
      missions = @season.season_objectives.legacy.order(:position)
      return nil if missions.empty?

      missions.map do |mission|
        {
          "key" => mission.name,
          "metric" => mission.metric_key,
          "target" => mission.target,
          "options" => mission.options.presence,
          "xp_reward" => mission.xp_reward,
          "coin_reward" => mission.coin_reward,
          "fragment_reward" => mission.fragment_reward,
          "icon" => mission.icon
        }.compact
      end
    end

    def daily_templates
      templates = DailyChallengeTemplate.where(season_id: @season.id).order(:key)
      return nil if templates.empty?

      templates.map do |template|
        {
          "key" => template.key,
          "metric" => template.metric,
          "target" => numeric(template.target),
          "options" => template.options.presence,
          "sport" => template.sport,
          "xp_reward" => template.xp_reward,
          "coin_reward" => template.coin_reward,
          "weight" => template.weight,
          "requires_start_time" => (template.requires_start_time? || nil)
        }.compact
      end
    end

    def community_goal
      goal = @season.season_community_goals.first
      return nil if goal.nil?

      {
        "key" => goal.key,
        "metric" => goal.metric,
        "target_mode" => goal.target_mode,
        "per_participant" => numeric(goal.per_participant),
        "target_value" => numeric(goal.base_target_value || goal.target_value),
        "tier_coin_reward" => goal.tier_coin_reward,
        "max_tiers" => goal.max_tiers,
        # Only tier 1 is exported; later tiers are created as they are cleared.
        "milestones" => goal.season_community_milestones.for_tier(1).order(:percent).map do |milestone|
          { "percent" => milestone.percent, "reward_key" => milestone.season_reward&.reward_key }.compact
        end
      }.compact
    end

    def cosmetics
      keys = @season.season_rewards.where(reward_type: "cosmetic").pluck(:reward_key).uniq
      return nil if keys.empty?

      Cosmetic.where(key: keys).order(:key).map do |cosmetic|
        {
          "key" => cosmetic.key,
          "kind" => cosmetic.kind,
          "name" => cosmetic.name,
          "rarity" => cosmetic.rarity,
          "css_class" => cosmetic.css_class,
          "icon" => cosmetic.icon,
          "animated" => (cosmetic.animated? || nil),
          "renderable" => (cosmetic.renderable? ? nil : false)
        }.compact
      end
    end

    # Keeps 15.0 as 15 so the YAML reads like the hand-written blueprints.
    def numeric(value)
      return nil if value.nil?

      float = value.to_f
      float == float.to_i ? float.to_i : float
    end
  end
end
