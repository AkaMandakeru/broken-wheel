# frozen_string_literal: true

module SeasonsHelper
  # Gradient classes for a season's visual theme.
  def season_theme_classes(theme)
    case theme
    when "summer" then "from-orange-400 via-amber-400 to-yellow-300"
    when "winter" then "from-sky-500 via-blue-500 to-indigo-500"
    when "spring" then "from-emerald-400 via-green-400 to-lime-300"
    when "autumn" then "from-amber-600 via-orange-500 to-red-500"
    # Legacy of Champions: dark blue, gold and silver.
    when "legacy" then "from-slate-900 via-blue-900 to-amber-500"
    else "from-primary via-primary/90 to-secondary"
    end
  end

  # A resized variant of the season's picture, or nil when there isn't one.
  #
  # Falls back to the original file when the blob can't be transformed — an
  # upload that isn't a processable image would otherwise raise at render time
  # and take the whole page down.
  def season_image_source(season, resize:)
    return nil unless season&.image&.attached?

    season.image.variable? ? season.image.variant(resize_to_fill: resize) : season.image
  rescue ActiveStorage::Error, ActiveStorage::FileNotFoundError
    nil
  end

  def season_status_badge_class(status)
    case status
    when "active"   then "bg-green-100 text-green-700"
    when "upcoming" then "bg-blue-100 text-blue-700"
    else "bg-gray-100 text-gray-600"
    end
  end

  def season_activity_text(activity)
    meta = activity.metadata || {}
    case activity.kind
    when "challenge_completed"
      t("seasons.activity.challenge_completed", challenge: meta["challenge"], xp: meta["xp"])
    when "objective_completed"
      t("seasons.activity.objective_completed", objective: meta["objective"], xp: meta["xp"])
    when "level_up"
      t("seasons.activity.level_up", level: meta["level"])
    when "reward_unlocked"
      t("seasons.activity.reward_unlocked", name: meta["name"].presence || meta["reward_key"])
    when "daily_completed"
      t("seasons.activity.daily_completed", daily: meta["daily"], xp: meta["xp"])
    when "secret_discovered"
      t("seasons.activity.secret_discovered", challenge: meta["challenge"], xp: meta["xp"])
    when "legacy_mission_completed"
      t("seasons.activity.legacy_mission_completed", objective: meta["objective"], xp: meta["xp"])
    when "community_milestone"
      t("seasons.activity.community_milestone", percent: meta["percent"], goal: meta["title"].presence || meta["goal"])
    when "community_tier_cleared"
      t("seasons.activity.community_tier_cleared",
        goal: meta["title"].presence || meta["goal"], tier: meta["tier"],
        next_tier: meta["next_tier"], next_target: number_with_delimiter(meta["next_target"].to_f.round))
    when "season_finalized"
      t("seasons.activity.season_finalized", level: meta["level"], percent: meta["completion_percent"])
    else
      activity.kind
    end
  end

  def season_reward_label(reward)
    case reward.reward_type
    when "title" then Titles.label(reward.reward_key)
    when "coins" then t("seasons.rewards.coins", count: reward.coins)
    else reward.name.presence || reward.reward_key.to_s.humanize
    end
  end

  def season_reward_icon(reward)
    case reward.reward_type
    when "title"    then "fa-solid fa-id-badge"
    when "badge"    then "fa-solid fa-medal"
    when "theme"    then "fa-solid fa-palette"
    when "coins"    then "fa-solid fa-coins"
    when "cosmetic" then "fa-solid fa-wand-magic-sparkles"
    when "xp_boost" then "fa-solid fa-bolt"
    else "fa-solid fa-gift"
    end
  end

  def season_category_icon(category)
    case category
    when "weekly"  then "fa-solid fa-calendar-week"
    when "monthly" then "fa-solid fa-calendar-days"
    when "elite"   then "fa-solid fa-crown"
    when "hidden"  then "fa-solid fa-user-secret"
    when "daily"   then "fa-solid fa-sun"
    else "fa-solid fa-flag-checkered"
    end
  end

  def medal_tier_classes(tier)
    case tier
    when "bronze"  then "bg-amber-100 text-amber-800"
    when "silver"  then "bg-slate-200 text-slate-700"
    when "gold"    then "bg-yellow-100 text-yellow-700"
    when "diamond" then "bg-cyan-100 text-cyan-700"
    else "bg-gray-100 text-gray-500"
    end
  end

  def cosmetic_rarity_classes(rarity)
    case rarity
    when "rare"      then "bg-sky-100 text-sky-700"
    when "epic"      then "bg-purple-100 text-purple-700"
    when "legendary" then "bg-amber-100 text-amber-700"
    else "bg-gray-100 text-gray-600"
    end
  end

  # Formats a metric value for display — seconds become m:ss, distances keep
  # one decimal, counts stay whole.
  def format_metric_value(value, unit)
    return "—" if value.nil?

    case unit
    when "seconds" then format("%d:%02d", value.to_i / 60, value.to_i % 60)
    when "km"      then "#{number_with_precision(value, precision: value.to_f == value.to_i ? 0 : 1)} km"
    when "m"       then "#{number_with_delimiter(value.to_i)} m"
    when "boolean" then value.to_f.positive? ? t("seasons.show.done") : t("seasons.show.not_yet")
    else number_with_delimiter(value.to_i)
    end
  end

  def leaderboard_value_label(board, value)
    return "—" if value.nil?

    case board
    when :distance   then "#{number_with_precision(value, precision: 1)} km"
    when :elevation  then "#{number_with_delimiter(value.to_i)} m"
    when :fastest_5k then format("%d:%02d", value.to_i / 60, value.to_i % 60)
    when :streak     then t("seasons.leaderboards.days", count: value.to_i)
    when :activities then t("seasons.leaderboards.activities", count: value.to_i)
    else "#{number_with_delimiter(value.to_i)} XP"
    end
  end
end
