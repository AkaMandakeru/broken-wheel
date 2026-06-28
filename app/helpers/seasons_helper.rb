# frozen_string_literal: true

module SeasonsHelper
  # Gradient classes for a season's visual theme.
  def season_theme_classes(theme)
    case theme
    when "summer" then "from-orange-400 via-amber-400 to-yellow-300"
    when "winter" then "from-sky-500 via-blue-500 to-indigo-500"
    when "spring" then "from-emerald-400 via-green-400 to-lime-300"
    when "autumn" then "from-amber-600 via-orange-500 to-red-500"
    else "from-primary via-primary/90 to-secondary"
    end
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
    else
      activity.kind
    end
  end

  def season_reward_label(reward)
    case reward.reward_type
    when "title" then Titles.label(reward.reward_key)
    else reward.name.presence || reward.reward_key.to_s.humanize
    end
  end
end
