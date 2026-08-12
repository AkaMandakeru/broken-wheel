# frozen_string_literal: true

module Seasons
  # Checks a blueprint before anything touches the database.
  #
  # An import creates records across nine tables; a typo two thirds of the way
  # down would otherwise leave a half-built season behind. Every problem is
  # reported at once, with the path that caused it, so a blueprint can be fixed
  # in one pass rather than one error per attempt.
  class BlueprintValidator
    MAX_MILESTONE_PERCENT = 100

    attr_reader :errors, :warnings

    def self.call(data)
      new(data).tap(&:validate)
    end

    def initialize(data)
      @data = data
      @errors = []
      @warnings = []
    end

    def valid?
      errors.empty?
    end

    def validate
      return error("", "the blueprint must be a YAML mapping (key: value), not #{@data.class.name.downcase}") unless @data.is_a?(Hash)

      validate_season
      validate_challenges
      validate_rewards
      validate_legacy_missions
      validate_daily_templates
      validate_community_goal
      self
    end

    # A short human summary of what the import would create.
    def summary
      return {} unless @data.is_a?(Hash)

      {
        challenges: Array(@data["challenges"]).size,
        rewards: Array(@data["rewards"]).size,
        legacy_missions: Array(@data["legacy_missions"]).size,
        daily_templates: Array(@data["daily_templates"]).size,
        cosmetics: Array(@data["cosmetics"]).size,
        community_goal: @data["community_goal"].present? ? 1 : 0
      }
    end

    private

    def error(path, message)
      @errors << (path.present? ? "#{path}: #{message}" : message)
      nil
    end

    def warn(path, message)
      @warnings << (path.present? ? "#{path}: #{message}" : message)
      nil
    end

    # --- Season -------------------------------------------------------------

    def validate_season
      %w[key name starts_at ends_at].each do |field|
        error(field, "is required") if @data[field].blank?
      end

      if @data["key"].present? && @data["key"].to_s !~ /\A[a-z0-9_]+\z/
        error("key", "must be lowercase letters, numbers and underscores only (got #{@data['key'].inspect})")
      end

      validate_dates
      validate_levels

      theme = @data["theme"]
      if theme.present? && !Season::THEMES.include?(theme.to_s)
        error("theme", "#{theme.inspect} is not a theme. Options: #{Season::THEMES.join(', ')}")
      end

      status = @data["status"]
      if status.present? && !Season::STATUSES.include?(status.to_s)
        error("status", "#{status.inspect} is not a status. Options: #{Season::STATUSES.join(', ')}")
      end

      zone = @data["time_zone"]
      error("time_zone", "#{zone.inspect} is not a known timezone") if zone.present? && ActiveSupport::TimeZone[zone.to_s].nil?
    end

    def validate_dates
      starts_at = parse_date(@data["starts_at"])
      ends_at   = parse_date(@data["ends_at"])

      error("starts_at", "is not a date (use YYYY-MM-DD)") if @data["starts_at"].present? && starts_at.nil?
      error("ends_at", "is not a date (use YYYY-MM-DD)") if @data["ends_at"].present? && ends_at.nil?
      return unless starts_at && ends_at

      error("ends_at", "must be after starts_at") if ends_at < starts_at
    end

    def validate_levels
      max_level = @data["max_level"]
      if max_level.present?
        unless max_level.to_i.between?(1, Season::MAX_SUPPORTED_LEVEL)
          error("max_level", "must be between 1 and #{Season::MAX_SUPPORTED_LEVEL} (got #{max_level.inspect})")
        end
      end

      top = @data["top_level_xp"]
      error("top_level_xp", "must be greater than 0") if top.present? && top.to_i <= 0

      exponent = @data["curve_exponent"]
      error("curve_exponent", "must be greater than 0") if exponent.present? && exponent.to_f <= 0
    end

    # --- Challenges ---------------------------------------------------------

    def validate_challenges
      entries = @data["challenges"]
      return if entries.blank?
      return error("challenges", "must be a list") unless entries.is_a?(Array)

      seen = {}
      entries.each_with_index do |entry, index|
        path = "challenges[#{index}]"
        next error(path, "must be a mapping") unless entry.is_a?(Hash)

        key = entry["key"]
        if key.blank?
          error(path, "key is required")
        elsif seen.key?(key)
          error(path, "key #{key.inspect} is already used by challenges[#{seen[key]}]")
        else
          seen[key] = index
        end

        validate_challenge_category(entry, path)
        validate_challenge_window(entry, path)
        validate_requirements(entry, path)
      end
    end

    def validate_challenge_category(entry, path)
      category = entry["category"]
      if category.present? && !SeasonChallenge::CATEGORIES.include?(category.to_s)
        error("#{path}.category", "#{category.inspect} is not a category. Options: #{SeasonChallenge::CATEGORIES.join(', ')}")
      end

      unlock = entry["unlock_level"]
      return if unlock.blank?

      max_level = (@data["max_level"] || 10).to_i
      if unlock.to_i > max_level
        error("#{path}.unlock_level", "is #{unlock} but the season only has #{max_level} levels, so it could never unlock")
      end
    end

    # Dates copied from the season a challenge came from are the usual cause of
    # a window that scores nothing.
    def validate_challenge_window(entry, path)
      starts_at = parse_date(entry["starts_at"])
      ends_at   = parse_date(entry["ends_at"])
      return if starts_at.nil? && ends_at.nil?

      if starts_at && ends_at && ends_at < starts_at
        error("#{path}.ends_at", "must be after starts_at")
      end

      season_start = parse_date(@data["starts_at"])
      season_end   = parse_date(@data["ends_at"])
      return unless season_start && season_end

      if starts_at && (starts_at < season_start || starts_at > season_end)
        error("#{path}.starts_at", "#{starts_at} is outside the season (#{season_start}..#{season_end})")
      end
      if ends_at && (ends_at < season_start || ends_at > season_end)
        error("#{path}.ends_at", "#{ends_at} is outside the season (#{season_start}..#{season_end})")
      end
    end

    def validate_requirements(entry, path)
      requirements = entry["requirements"]
      return error("#{path}.requirements", "at least one requirement is required") if requirements.blank?
      return error("#{path}.requirements", "must be a list") unless requirements.is_a?(Array)

      requirements.each_with_index do |requirement, index|
        rpath = "#{path}.requirements[#{index}]"
        next error(rpath, "must be a mapping") unless requirement.is_a?(Hash)

        validate_metric(requirement["metric"], "#{rpath}.metric")

        target = requirement["target"]
        if target.blank?
          error("#{rpath}.target", "is required")
        elsif target.to_f <= 0
          error("#{rpath}.target", "must be greater than 0")
        end

        comparator = requirement["comparator"]
        if comparator.present? && !ChallengeRequirement::COMPARATORS.include?(comparator.to_s)
          error("#{rpath}.comparator", "must be one of: #{ChallengeRequirement::COMPARATORS.join(', ')}")
        end
      end
    end

    def validate_metric(metric, path)
      return error(path, "is required") if metric.blank?
      return if ChallengeMetrics.exists?(metric)

      error(path, "#{metric.inspect} is not a known metric.#{did_you_mean(metric)} All metrics: #{ChallengeMetrics.keys.join(', ')}")
    end

    def did_you_mean(metric)
      close = ChallengeMetrics.keys.select { |k| k.start_with?(metric.to_s[0, 3].to_s) || k.include?(metric.to_s) }
      close.any? ? " Did you mean #{close.first(3).map(&:inspect).join(' or ')}?" : ""
    end

    # --- Rewards ------------------------------------------------------------

    def validate_rewards
      entries = @data["rewards"]
      return if entries.blank?
      return error("rewards", "must be a list") unless entries.is_a?(Array)

      max_level = (@data["max_level"] || 10).to_i
      cosmetic_keys = Array(@data["cosmetics"]).filter_map { |c| c["key"] if c.is_a?(Hash) }

      entries.each_with_index do |entry, index|
        path = "rewards[#{index}]"
        next error(path, "must be a mapping") unless entry.is_a?(Hash)

        error("#{path}.reward_key", "is required") if entry["reward_key"].blank?

        type = entry["reward_type"]
        if type.blank?
          error("#{path}.reward_type", "is required")
        elsif !SeasonReward::REWARD_TYPES.include?(type.to_s)
          error("#{path}.reward_type", "#{type.inspect} is not valid. Options: #{SeasonReward::REWARD_TYPES.join(', ')}")
        end

        track = entry["track"]
        if track.present? && !SeasonReward::TRACKS.include?(track.to_s)
          error("#{path}.track", "#{track.inspect} is not valid. Options: #{SeasonReward::TRACKS.join(', ')}")
        end

        validate_reward_unlock(entry, path, max_level)
        validate_reward_payload(entry, path, cosmetic_keys)
      end
    end

    def validate_reward_unlock(entry, path, max_level)
      unlock_kind = entry.fetch("unlock_kind", "level").to_s
      unless SeasonReward::UNLOCK_KINDS.include?(unlock_kind)
        return error("#{path}.unlock_kind", "#{unlock_kind.inspect} is not valid. Options: #{SeasonReward::UNLOCK_KINDS.join(', ')}")
      end

      if unlock_kind == "level"
        level = entry["level"]
        if level.blank?
          error("#{path}.level", "is required for a level reward")
        elsif level.to_i > max_level
          error("#{path}.level", "is #{level} but the season only has #{max_level} levels, so it could never be granted")
        elsif level.to_i < 1
          error("#{path}.level", "must be at least 1")
        end
      elsif entry["unlock_value"].blank?
        error("#{path}.unlock_value", "is required for a #{unlock_kind} reward")
      end
    end

    def validate_reward_payload(entry, path, cosmetic_keys)
      case entry["reward_type"].to_s
      when "coins"
        error("#{path}.coins", "must be greater than 0 for a coins reward") if entry["coins"].to_i <= 0
      when "cosmetic"
        key = entry["reward_key"].to_s
        return if key.blank? || cosmetic_keys.include?(key) || Cosmetic.exists?(key: key)

        error("#{path}.reward_key", "cosmetic #{key.inspect} is not defined in this blueprint's `cosmetics:` list and does not already exist")
      when "title"
        key = entry["reward_key"].to_s
        warn("#{path}.reward_key", "title #{key.inspect} is not in config/titles.yml, so it will not display a label") unless key.blank? || Titles.exists?(key)
      end
    end

    # --- Legacy missions ----------------------------------------------------

    def validate_legacy_missions
      entries = @data["legacy_missions"]
      return if entries.blank?
      return error("legacy_missions", "must be a list") unless entries.is_a?(Array)

      entries.each_with_index do |entry, index|
        path = "legacy_missions[#{index}]"
        next error(path, "must be a mapping") unless entry.is_a?(Hash)

        error("#{path}.key", "is required") if entry["key"].blank?
        validate_metric(entry["metric"], "#{path}.metric")
        error("#{path}.target", "must be greater than 0") if entry["target"].to_f <= 0
      end
    end

    # --- Daily templates ----------------------------------------------------

    def validate_daily_templates
      entries = @data["daily_templates"]
      return if entries.blank?
      return error("daily_templates", "must be a list") unless entries.is_a?(Array)

      seen = {}
      entries.each_with_index do |entry, index|
        path = "daily_templates[#{index}]"
        next error(path, "must be a mapping") unless entry.is_a?(Hash)

        key = entry["key"]
        if key.blank?
          error(path, "key is required")
        elsif seen.key?(key)
          error(path, "key #{key.inspect} is already used by daily_templates[#{seen[key]}]")
        else
          seen[key] = index
        end

        validate_metric(entry["metric"], "#{path}.metric")
        error("#{path}.target", "must be greater than 0") if entry["target"].to_f <= 0
      end

      # Three are drawn per user per day; a smaller pool means everyone sees the
      # same set every day.
      warn("daily_templates", "only #{entries.size} template(s) — three are drawn per day, so add more for variety") if entries.size < DailyChallenges::Assigner::PER_DAY + 2
    end

    # --- Community goal -----------------------------------------------------

    def validate_community_goal
      goal = @data["community_goal"]
      return if goal.blank?
      return error("community_goal", "must be a mapping") unless goal.is_a?(Hash)

      error("community_goal.key", "is required") if goal["key"].blank?

      metric = goal["metric"]
      validate_metric(metric, "community_goal.metric")
      if metric.present? && ChallengeMetrics.exists?(metric) && !Seasons::CommunityAggregator::AGGREGATABLE.key?(metric.to_s)
        error("community_goal.metric", "#{metric.inspect} cannot be summed across a community. Options: #{Seasons::CommunityAggregator::AGGREGATABLE.keys.join(', ')}")
      end

      mode = goal.fetch("target_mode", "fixed").to_s
      unless SeasonCommunityGoal::TARGET_MODES.include?(mode)
        error("community_goal.target_mode", "#{mode.inspect} is not valid. Options: #{SeasonCommunityGoal::TARGET_MODES.join(', ')}")
      end

      if mode == "per_participant" && goal["per_participant"].to_f <= 0
        error("community_goal.per_participant", "must be greater than 0 when target_mode is per_participant")
      end

      if mode == "fixed" && goal["target_value"].to_f <= 0
        error("community_goal.target_value", "must be greater than 0 when target_mode is fixed")
      end

      validate_milestones(goal)
    end

    def validate_milestones(goal)
      milestones = goal["milestones"]
      return if milestones.blank?
      return error("community_goal.milestones", "must be a list") unless milestones.is_a?(Array)

      milestones.each_with_index do |milestone, index|
        path = "community_goal.milestones[#{index}]"
        percent = milestone.is_a?(Hash) ? milestone["percent"] : milestone

        if percent.blank?
          error(path, "percent is required")
        elsif !percent.to_i.between?(1, MAX_MILESTONE_PERCENT)
          error(path, "percent must be between 1 and #{MAX_MILESTONE_PERCENT} (got #{percent.inspect})")
        end
      end
    end

    def parse_date(value)
      return nil if value.blank?
      return value.to_date if value.respond_to?(:to_date)

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
