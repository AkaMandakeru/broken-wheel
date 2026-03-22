# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Sample Challenges
# ---------------------------------------------------------------------------

Challenge.find_or_create_by!(title: "Weekly Run 20km") do |c|
  c.description = "Run 20km this week"
  c.challenge_type = "weekly"
  c.sport = "run"
  c.target_value = 20
  c.target_unit = "km"
  c.starts_at = Date.current.beginning_of_week
  c.ends_at = Date.current.end_of_week
  c.status = "active"
end

Challenge.find_or_create_by!(title: "Monthly Bike 200km") do |c|
  c.description = "Bike 200km this month"
  c.challenge_type = "monthly"
  c.sport = "bike"
  c.target_value = 200
  c.target_unit = "km"
  c.starts_at = Date.current.beginning_of_month
  c.ends_at = Date.current.end_of_month
  c.status = "active"
end

# ---------------------------------------------------------------------------
# Achievements
# ---------------------------------------------------------------------------

def upsert_badge(badge_type:, name:, icon:, description:, title:, points:, threshold_value: nil, threshold_distance: nil)
  badge = Badge.find_or_initialize_by(badge_type: badge_type, name: name)
  badge.update!(
    icon: icon,
    description: description,
    title: title,
    points: points,
    threshold_value: threshold_value,
    threshold_distance: threshold_distance
  )
end

# ---------------------------------------------------------------------------
# 1. Workout Count
#    Awarded when total running workouts reach a threshold.
# ---------------------------------------------------------------------------

WORKOUT_COUNT_TIERS = [
  { threshold: 1,   name: "First Revolution",  icon: "🔰", title: "Rookie",    points: 10   },
  { threshold: 5,   name: "Getting Rolling",   icon: "🚲", title: "Sprout",    points: 25   },
  { threshold: 10,  name: "Finding the Groove", icon: "🎵", title: "Regular",   points: 50   },
  { threshold: 25,  name: "Road Familiar",      icon: "🛣️", title: "Committed", points: 100  },
  { threshold: 50,  name: "Iron Wheels",        icon: "⚙️", title: "Dedicated", points: 200  },
  { threshold: 100, name: "Century Crusher",    icon: "💯", title: "Centurion", points: 500  },
  { threshold: 200, name: "Double Down",        icon: "⚡", title: "Veteran",   points: 1000 },
  { threshold: 300, name: "Triple Crown",       icon: "👑", title: "Elite",     points: 1500 },
  { threshold: 400, name: "Relentless",         icon: "🔥", title: "Legend",    points: 2000 },
  { threshold: 500, name: "Wheel Breaker",      icon: "🏆", title: "Champion",  points: 3000 },
].freeze

WORKOUT_COUNT_TIERS.each do |tier|
  upsert_badge(
    badge_type: "workout_count",
    name: tier[:name],
    icon: tier[:icon],
    description: "Complete #{tier[:threshold]} running workouts.",
    title: tier[:title],
    points: tier[:points],
    threshold_value: tier[:threshold]
  )
end

# ---------------------------------------------------------------------------
# 2. Distance PRs
#    Awarded the first time a user logs a run of at least this distance.
# ---------------------------------------------------------------------------

DISTANCE_PR_TIERS = [
  { distance: 3,  name: "First Stretch",    icon: "🌱", title: "Explorer",               points: 20   },
  { distance: 5,  name: "Park Debut",       icon: "🌳", title: "Mover",                  points: 30   },
  { distance: 8,  name: "Eight Miles Out",  icon: "🛤️", title: "Strider",                points: 50   },
  { distance: 10, name: "Dime Drop",        icon: "💧", title: "Runner",                 points: 75   },
  { distance: 15, name: "Halfway Hero",     icon: "⭐", title: "Adventurer",             points: 100  },
  { distance: 20, name: "Score Setter",     icon: "🏙️", title: "Endurance Seeker",       points: 150  },
  { distance: 21, name: "Half the Journey", icon: "🥈", title: "Half-Marathoner",        points: 200  },
  { distance: 25, name: "Quarter Century",  icon: "⚡", title: "Distance Warrior",       points: 250  },
  { distance: 30, name: "Dirty Thirty",     icon: "💪", title: "Iron Runner",            points: 350  },
  { distance: 40, name: "The Forty",        icon: "🎯", title: "Marathoner-in-Training", points: 450  },
  { distance: 42, name: "Full Disclosure",  icon: "🏅", title: "Marathoner",             points: 600  },
  { distance: 50, name: "Ultra Pioneer",    icon: "🌋", title: "Ultra Runner",           points: 1000 },
].freeze

DISTANCE_PR_TIERS.each do |tier|
  upsert_badge(
    badge_type: "distance_pr",
    name: tier[:name],
    icon: tier[:icon],
    description: "Run #{tier[:distance]}km for the first time.",
    title: tier[:title],
    points: tier[:points],
    threshold_distance: tier[:distance]
  )
end

# ---------------------------------------------------------------------------
# 3. Distance Count
#    For each key distance, awarded every time the user hits a count threshold.
#    12 distances × 10 thresholds = 120 badges.
# ---------------------------------------------------------------------------

DISTANCE_SERIES = [
  { distance: 3,  series: "Sprint",         icon: "💨", base_points: 5  },
  { distance: 5,  series: "Park Run",       icon: "🌳", base_points: 8  },
  { distance: 8,  series: "Eight",          icon: "🔢", base_points: 12 },
  { distance: 10, series: "Dime Club",      icon: "💧", base_points: 15 },
  { distance: 15, series: "Fifteen",        icon: "🌟", base_points: 20 },
  { distance: 20, series: "Score",          icon: "🏙️", base_points: 25 },
  { distance: 21, series: "Half-Marathon",  icon: "🥈", base_points: 30 },
  { distance: 25, series: "Quarter",        icon: "⚡", base_points: 35 },
  { distance: 30, series: "Thirty",         icon: "💪", base_points: 45 },
  { distance: 40, series: "Forty",          icon: "🎯", base_points: 55 },
  { distance: 42, series: "Marathon",       icon: "🏅", base_points: 65 },
  { distance: 50, series: "Ultra",          icon: "🌋", base_points: 80 },
].freeze

COUNT_TIERS = [
  { count: 1,   suffix: "Rookie",    multiplier: 1.0  },
  { count: 5,   suffix: "Novice",    multiplier: 1.5  },
  { count: 10,  suffix: "Regular",   multiplier: 2.0  },
  { count: 25,  suffix: "Committed", multiplier: 3.0  },
  { count: 50,  suffix: "Dedicated", multiplier: 4.0  },
  { count: 100, suffix: "Centurion", multiplier: 6.0  },
  { count: 200, suffix: "Veteran",   multiplier: 8.0  },
  { count: 300, suffix: "Elite",     multiplier: 10.0 },
  { count: 400, suffix: "Legend",    multiplier: 12.0 },
  { count: 500, suffix: "Champion",  multiplier: 15.0 },
].freeze

DISTANCE_SERIES.each do |series|
  COUNT_TIERS.each do |tier|
    points = (series[:base_points] * tier[:multiplier]).round
    upsert_badge(
      badge_type: "distance_count",
      name: "#{series[:series]} #{tier[:suffix]}",
      icon: series[:icon],
      description: "Complete #{tier[:count]} runs of #{series[:distance]}km or more.",
      title: tier[:suffix],
      points: points,
      threshold_value: tier[:count],
      threshold_distance: series[:distance]
    )
  end
end

# ---------------------------------------------------------------------------
# 4. Consistency Streaks
#    Awarded for consecutive calendar weeks with at least one running workout.
# ---------------------------------------------------------------------------

STREAK_TIERS = [
  { threshold: 1,   name: "First Week Out",        icon: "📅", title: "Consistent Rookie", points: 15   },
  { threshold: 5,   name: "High Five Weeks",        icon: "✋", title: "Week Warrior",      points: 50   },
  { threshold: 10,  name: "Double Digit Streak",    icon: "🔟", title: "Habit Builder",     points: 100  },
  { threshold: 25,  name: "Quarter Year Grind",     icon: "📆", title: "Rhythm Keeper",     points: 250  },
  { threshold: 50,  name: "Half Century Streak",    icon: "🌗", title: "Streak Machine",    points: 500  },
  { threshold: 100, name: "Century Streak",         icon: "💯", title: "Ironclad",          points: 1000 },
  { threshold: 200, name: "Two Hundred Strong",     icon: "⚡", title: "Unstoppable",       points: 2000 },
  { threshold: 300, name: "Relentless Rhythm",      icon: "🌊", title: "Streak Legend",     points: 3000 },
  { threshold: 400, name: "Four Hundred Reasons",   icon: "🔥", title: "Streak Elite",      points: 4000 },
  { threshold: 500, name: "Eternal Flame",          icon: "🕯️", title: "Streak Champion",   points: 5000 },
].freeze

STREAK_TIERS.each do |tier|
  upsert_badge(
    badge_type: "streak",
    name: tier[:name],
    icon: tier[:icon],
    description: "Maintain a running streak for #{tier[:threshold]} consecutive week(s).",
    title: tier[:title],
    points: tier[:points],
    threshold_value: tier[:threshold]
  )
end

# ---------------------------------------------------------------------------
# 5. Pace Achievements
#    Awarded for running a distance at or faster than a given pace (min/km).
#    Only for 5km, 10km, and 21km. Starting from 6:00/km.
# ---------------------------------------------------------------------------

PACE_DISTANCES = [
  { distance: 5,  label: "5K",            multiplier: 1.0 },
  { distance: 10, label: "10K",           multiplier: 1.5 },
  { distance: 21, label: "Half-Marathon", multiplier: 2.0 },
].freeze

PACE_TIERS = [
  { pace: 6.0, name: "Cruiser",   icon: "🐢", title: "Pace Rookie",    base_points: 50   },
  { pace: 5.5, name: "Pacer",     icon: "🦶", title: "Trail Pacer",    base_points: 100  },
  { pace: 5.0, name: "Swift",     icon: "💨", title: "Speed Seeker",   base_points: 200  },
  { pace: 4.5, name: "Rapid",     icon: "⚡", title: "Fast Tracker",   base_points: 350  },
  { pace: 4.0, name: "Blazer",    icon: "🔥", title: "Blazer",         base_points: 600  },
  { pace: 3.5, name: "Lightning", icon: "⚡", title: "Speed Champion", base_points: 1000 },
].freeze

def format_pace(pace_float)
  minutes = pace_float.to_i
  seconds = ((pace_float % 1) * 60).round
  "#{minutes}:#{seconds.to_s.rjust(2, '0')}/km"
end

PACE_DISTANCES.each do |dist|
  PACE_TIERS.each do |tier|
    points = (tier[:base_points] * dist[:multiplier]).round
    upsert_badge(
      badge_type: "pace",
      name: "#{dist[:label]} #{tier[:name]}",
      icon: tier[:icon],
      description: "Run #{dist[:distance]}km at #{format_pace(tier[:pace])} pace or faster.",
      title: tier[:title],
      points: points,
      threshold_value: tier[:pace],
      threshold_distance: dist[:distance]
    )
  end
end

puts "✅ Seeded #{Badge.count} badges across #{Badge.distinct.pluck(:badge_type).size} categories."
