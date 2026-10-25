# frozen_string_literal: true

# OpenAPI schemas for the season endpoints (spec/requests/api/v1/seasons*).
# Kept beside the specs rather than in swagger_helper.rb, which is shared.
module SeasonsSchemas
  nullable_string = { type: :string, nullable: true }
  nullable_integer = { type: :integer, nullable: true }
  nullable_number = { type: :number, nullable: true }
  image = { "$ref" => "#/components/schemas/image" }

  SEASON = {
    type: :object,
    required: %w[id key name theme status status_label time_zone max_level current_date battle_pass image],
    properties: {
      id: { type: :integer },
      key: nullable_string,
      name: { type: :string },
      slogan: nullable_string,
      description: nullable_string,
      theme: { type: :string, enum: Season::THEMES },
      status: { type: :string, enum: Season::STATUSES },
      status_label: { type: :string },
      starts_at: { type: :string, format: "date-time", nullable: true },
      ends_at: { type: :string, format: "date-time", nullable: true },
      time_zone: { type: :string, example: "America/Sao_Paulo" },
      current_date: { type: :string, format: :date, description: "Today in the season's timezone" },
      max_level: { type: :integer },
      battle_pass: { type: :boolean },
      image: image
    }
  }.freeze

  SEASON_DETAIL = SEASON.merge(
    required: SEASON[:required] + [ "level_curve" ],
    properties: SEASON[:properties].merge(
      level_curve: { type: :array, items: { type: :integer }, description: "XP needed for each level; index 0 is level 1" }
    )
  ).freeze

  PARTICIPATION = {
    type: :object,
    required: %w[xp level premium rank progress_percent xp_to_next_level unclaimed_count unclaimed_xp coins medal],
    properties: {
      xp: { type: :integer },
      level: { type: :integer },
      max_level_reached: { type: :boolean },
      premium: { type: :boolean },
      rank: { type: :integer },
      progress_percent: { type: :integer },
      xp_to_next_level: { type: :integer },
      unclaimed_count: { type: :integer },
      unclaimed_xp: { type: :integer },
      coins: { type: :integer, description: "The player's coin balance" },
      coins_earned: { type: :integer, description: "Coins earned in this season" },
      activities_count: { type: :integer },
      longest_streak_days: { type: :integer },
      completion_percent: { type: :integer },
      total_distance_km: { type: :number },
      elevation_gain_m: { type: :number },
      best_5k_seconds: nullable_integer,
      medal: {
        type: :object,
        required: %w[fragments progress_percent],
        properties: {
          tier: { type: :string, nullable: true, enum: SeasonParticipation::MEDAL_TIERS.keys + [ nil ] },
          fragments: { type: :integer },
          next_tier: nullable_string,
          fragments_to_next: { type: :integer },
          progress_percent: { type: :integer }
        }
      }
    }
  }.freeze

  medal = { type: :string, nullable: true, enum: Seasons::WeeklyMedals::TIERS + [ nil ] }

  CHALLENGE = {
    type: :object,
    required: %w[id challenge_id title category category_label xp_reward coin_reward unlock_level locked special
                 requirements progress narrower_than_season window_ended],
    properties: {
      id: { type: :integer, description: "Season challenge id" },
      challenge_id: { type: :integer },
      title: { type: :string },
      description: nullable_string,
      category: { type: :string, enum: SeasonChallenge::CATEGORIES },
      category_label: { type: :string },
      week_index: nullable_integer,
      position: { type: :integer },
      sport: nullable_string,
      image: image,
      xp_reward: { type: :integer },
      coin_reward: { type: :integer },
      fragment_reward: { type: :integer },
      required: { type: :boolean },
      unlock_level: { type: :integer },
      locked: { type: :boolean, description: "Below unlock_level" },
      special: { type: :boolean },
      elite: { type: :boolean },
      starts_on: { type: :string, format: :date, nullable: true },
      ends_on: { type: :string, format: :date, nullable: true },
      narrower_than_season: { type: :boolean, description: "Show the dates: they cover less than the season" },
      window_ended: { type: :boolean },
      requirements: {
        type: :array,
        items: {
          type: :object,
          required: %w[id metric label target unit progress],
          properties: {
            id: { type: :integer },
            metric: { type: :string },
            label: { type: :string },
            target: { type: :number },
            unit: { type: :string },
            comparator: { type: :string, enum: ChallengeRequirement::COMPARATORS },
            medal: medal.merge(description: "Weekly challenges only: the medal this requirement earns"),
            progress: {
              type: :object, nullable: true,
              properties: { value: nullable_number, percent: { type: :integer }, met: { type: :boolean } }
            }
          }
        }
      },
      progress: {
        type: :object, nullable: true, description: "Null for a guest or a challenge the player isn't in",
        required: %w[completed percent],
        properties: {
          completed: { type: :boolean },
          completed_at: { type: :string, format: "date-time", nullable: true },
          percent: { type: :integer },
          medal: medal.merge(description: "Weekly challenges only: the best medal earned")
        }
      }
    }
  }.freeze

  REWARD = {
    type: :object,
    required: %w[id track reward_type reward_key unlock_kind label unlock_label premium granted],
    properties: {
      id: { type: :integer },
      level: nullable_integer,
      track: { type: :string, enum: SeasonReward::TRACKS },
      reward_type: { type: :string, enum: SeasonReward::REWARD_TYPES },
      reward_key: { type: :string },
      unlock_kind: { type: :string, enum: SeasonReward::UNLOCK_KINDS },
      unlock_value: nullable_integer,
      coins: { type: :integer },
      label: { type: :string },
      unlock_label: { type: :string },
      premium: { type: :boolean },
      granted: { type: :boolean }
    }
  }.freeze

  OBJECTIVE = {
    type: :object,
    required: %w[id kind track title description target xp_reward completed],
    properties: {
      id: { type: :integer },
      kind: { type: :string, enum: SeasonObjective::KINDS },
      track: { type: :string, enum: SeasonObjective::TRACKS },
      icon: nullable_string,
      metric: { type: :string },
      title: { type: :string },
      description: { type: :string },
      target: { type: :integer },
      xp_reward: { type: :integer },
      coin_reward: { type: :integer },
      fragment_reward: { type: :integer },
      required: { type: :boolean },
      completed: { type: :boolean }
    }
  }.freeze

  DAILY = {
    type: :object,
    required: %w[id key title metric target xp_reward coin_reward challenge_date completed percent],
    properties: {
      id: { type: :integer },
      key: { type: :string },
      title: { type: :string },
      description: nullable_string,
      metric: { type: :string },
      sport: nullable_string,
      target: { type: :number },
      xp_reward: { type: :integer },
      coin_reward: { type: :integer },
      challenge_date: { type: :string, format: :date },
      completed: { type: :boolean },
      completed_at: { type: :string, format: "date-time", nullable: true },
      value: nullable_number.merge(description: "Live value from today's workouts"),
      percent: { type: :integer }
    }
  }.freeze

  ACTIVITY = {
    type: :object,
    required: %w[id kind text community created_at user],
    properties: {
      id: { type: :integer },
      kind: { type: :string, enum: SeasonActivity::KINDS },
      text: { type: :string, description: "Localised line, shown after the player's name" },
      community: { type: :boolean },
      created_at: { type: :string, format: "date-time" },
      user: { allOf: [ { "$ref" => "#/components/schemas/user_summary" } ], nullable: true }
    }
  }.freeze

  COMMUNITY_GOAL = {
    type: :object, nullable: true,
    required: %w[id key title unit tier tiers_cleared progress target percent_complete next_tier_target milestones],
    properties: {
      id: { type: :integer },
      key: { type: :string },
      title: { type: :string },
      description: nullable_string,
      metric: { type: :string },
      unit: { type: :string },
      tier: { type: :integer },
      tiers_cleared: { type: :integer },
      max_tiers: nullable_integer,
      final_tier: { type: :boolean },
      progress: { type: :number, description: "Amount covered in the current tier" },
      target: { type: :number, description: "What the current tier asks for" },
      percent_complete: { type: :integer },
      next_tier_target: { type: :number },
      tier_payout: { type: :integer },
      computed_at: { type: :string, format: "date-time", nullable: true },
      milestones: {
        type: :array,
        items: {
          type: :object,
          required: %w[id percent reached],
          properties: {
            id: { type: :integer },
            percent: { type: :integer },
            reached: { type: :boolean },
            reached_at: { type: :string, format: "date-time", nullable: true },
            reward: { allOf: [ REWARD ], nullable: true }
          }
        }
      }
    }
  }.freeze

  CLAIM = {
    type: :object,
    required: %w[id season_challenge_id title category xp completed_at],
    properties: {
      id: { type: :integer, description: "Completion id — POST …/claims/{id} to collect it" },
      season_challenge_id: { type: :integer },
      title: { type: :string },
      category: { type: :string, enum: SeasonChallenge::CATEGORIES },
      xp: { type: :integer },
      completed_at: { type: :string, format: "date-time" }
    }
  }.freeze

  CLAIM_RESULT = {
    type: :object,
    required: %w[claimed xp_gained xp level levelled_up progress_percent xp_to_next remaining],
    properties: {
      claimed: { type: :integer, description: "How many completions this call collected (0 when already claimed)" },
      xp_gained: { type: :integer },
      xp: { type: :integer },
      level: { type: :integer },
      levelled_up: { type: :boolean },
      progress_percent: { type: :integer },
      xp_to_next: { type: :integer },
      remaining: { type: :integer }
    }
  }.freeze

  LEADERBOARD = {
    type: :object,
    required: %w[board board_label unit boards rows me],
    properties: {
      board: { type: :string, enum: SeasonLeaderboard.boards.map(&:to_s) },
      board_label: { type: :string },
      unit: { type: :string, enum: %w[xp km count days seconds m] },
      boards: {
        type: :array,
        items: { type: :object, required: %w[key label], properties: { key: { type: :string }, label: { type: :string } } }
      },
      rows: {
        type: :array,
        items: {
          type: :object,
          required: %w[position value me user],
          properties: {
            position: { type: :integer },
            value: nullable_number,
            me: { type: :boolean },
            user: { "$ref" => "#/components/schemas/user_summary" }
          }
        }
      },
      me: {
        type: :object, nullable: true, description: "The viewer's place, even outside the top ten",
        properties: { position: nullable_integer, value: nullable_number }
      }
    }
  }.freeze

  OVERVIEW = {
    type: :object,
    required: %w[season participation announcement next_special_event],
    properties: {
      season: SEASON_DETAIL,
      participation: { allOf: [ PARTICIPATION ], nullable: true },
      announcement: {
        type: :object, nullable: true, description: "Null for a guest",
        required: %w[visible dismissed],
        properties: { visible: { type: :boolean }, dismissed: { type: :boolean } }
      },
      next_special_event: { allOf: [ CHALLENGE ], nullable: true }
    }
  }.freeze

  def self.data(schema)
    { type: :object, required: [ "data" ], properties: { data: schema } }
  end
end
