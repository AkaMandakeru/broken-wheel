# frozen_string_literal: true

# OpenAPI schemas for the player's own account, locker and achievements
# (spec/requests/api/v1/me*, locker_spec.rb, achievements_spec.rb). Kept beside
# the specs rather than in swagger_helper.rb, which is shared.
module ProfileSchemas
  nullable_string = { type: :string, nullable: true }
  nullable_integer = { type: :integer, nullable: true }
  image = { "$ref" => "#/components/schemas/image" }
  key_label = { type: :object, required: %w[key label], properties: { key: { type: :string }, label: { type: :string } } }

  # What the app needs to draw a cosmetic without the web's CSS classes.
  RENDER = {
    type: :object,
    nullable: true,
    required: %w[type colors],
    description: "Colours to draw the cosmetic with. Gradients run in the order given.",
    properties: {
      type: { type: :string, enum: %w[solid gradient] },
      colors: { type: :array, items: { type: :string, pattern: "^#[0-9a-f]{6}$", example: "#ffb900" } }
    }
  }.freeze

  COSMETIC = {
    type: :object,
    required: %w[key kind rarity name rarity_label image render],
    properties: {
      key: { type: :string },
      kind: { type: :string, enum: Cosmetic::KINDS },
      rarity: { type: :string, enum: Cosmetic::RARITIES },
      rarity_label: { type: :string },
      name: { type: :string },
      image: image.merge(description: "Banner/frame artwork (`original`, `display`); null until it is uploaded"),
      render: RENDER
    }
  }.freeze

  ME = {
    type: :object,
    required: %w[id email first_name last_name display_name coins title available_titles sports locale
                 email_reminders avatar connected_to_strava created_at equipped],
    properties: {
      id: { type: :integer },
      email: { type: :string },
      first_name: { type: :string },
      last_name: { type: :string },
      nickname: nullable_string,
      display_name: { type: :string },
      coins: { type: :integer },
      title: key_label.merge(nullable: true),
      available_titles: { type: :array, items: key_label },
      sports: { type: :array, items: { type: :string, enum: User::SPORTS } },
      locale: { type: :string, enum: I18n.available_locales.map(&:to_s) },
      email_reminders: { type: :boolean },
      avatar: image,
      document: nullable_string,
      phone: nullable_string,
      blood_type: nullable_string,
      address: nullable_string,
      connected_to_strava: { type: :boolean },
      created_at: { type: :string, format: "date-time" },
      equipped: {
        type: :object,
        required: Cosmetic::RENDERABLE_KINDS,
        properties: Cosmetic::RENDERABLE_KINDS.index_with { COSMETIC.merge(nullable: true) }
      }
    }
  }.freeze

  ME_UPDATE = {
    type: :object,
    required: [ "user" ],
    properties: {
      user: {
        type: :object,
        properties: {
          first_name: { type: :string },
          last_name: { type: :string },
          nickname: nullable_string,
          title: { type: :string, nullable: true, description: "Must be one of `available_titles`" },
          sports: { type: :array, items: { type: :string, enum: User::SPORTS } },
          document: nullable_string,
          phone: nullable_string,
          blood_type: nullable_string,
          address: nullable_string,
          email_reminders: { type: :boolean },
          locale: { type: :string, enum: I18n.available_locales.map(&:to_s) },
          avatar: { type: :string, nullable: true, description: "`signed_id` from POST /api/v1/uploads (purpose `avatar`); null removes the avatar" }
        }
      }
    }
  }.freeze

  STATS = {
    type: :object,
    required: %w[distance_km week_streak workouts seasons medals],
    properties: {
      distance_km: { type: :number },
      week_streak: { type: :integer },
      workouts: { type: :integer },
      seasons: { type: :integer },
      medals: { type: :integer }
    }
  }.freeze

  SEASON_REF = {
    type: :object,
    required: %w[id name],
    properties: { id: { type: :integer }, key: nullable_string, name: { type: :string } }
  }.freeze

  LOCKER = {
    type: :object,
    required: %w[kind kinds equipped_key owned claimable locked],
    properties: {
      kind: { type: :string, enum: Locker::Catalogue::KINDS },
      kinds: { type: :array, items: { type: :string, enum: Locker::Catalogue::KINDS } },
      equipped_key: nullable_string,
      owned: {
        type: :array,
        items: { allOf: [ COSMETIC, { type: :object, required: [ "equipped" ], properties: { equipped: { type: :boolean } } } ] }
      },
      claimable: {
        type: :array,
        description: "Offered by a season; take one with POST /api/v1/me/locker/claim",
        items: { allOf: [ COSMETIC, { type: :object, required: [ "season" ], properties: { season: SEASON_REF } } ] }
      },
      locked: {
        type: :array,
        items: {
          allOf: [
            COSMETIC,
            {
              type: :object,
              required: [ "unlock" ],
              properties: {
                unlock: {
                  type: :object, nullable: true, description: "Where to earn it; null when no season hands it out yet",
                  required: %w[season unlock_kind label],
                  properties: {
                    season: SEASON_REF,
                    unlock_kind: { type: :string, enum: SeasonReward::UNLOCK_KINDS },
                    unlock_value: nullable_integer,
                    label: { type: :string, example: "Level 12" }
                  }
                }
              }
            }
          ]
        }
      }
    }
  }.freeze

  CLAIM = {
    type: :object,
    required: %w[status cosmetic],
    properties: {
      status: { type: :string, enum: %w[claimed already_owned] },
      cosmetic: COSMETIC
    }
  }.freeze

  SEASON_MEDAL = {
    type: :object,
    required: %w[season level completion_percent medal_fragments medal_tier medal_label next_medal_tier
                 fragments_to_next_medal medal_progress_percent],
    properties: {
      season: {
        type: :object,
        required: %w[id name image browsable],
        properties: {
          id: { type: :integer },
          key: nullable_string,
          name: { type: :string },
          ends_at: { type: :string, format: "date-time", nullable: true },
          image: image,
          browsable: { type: :boolean, description: "Whether GET /api/v1/seasons/{id} opens it" }
        }
      },
      level: { type: :integer },
      completion_percent: { type: :integer },
      medal_fragments: { type: :integer },
      medal_tier: { type: :string, nullable: true, enum: [ *SeasonParticipation::MEDAL_TIERS.keys, nil ] },
      medal_label: nullable_string,
      next_medal_tier: { type: :string, nullable: true, enum: [ *SeasonParticipation::MEDAL_TIERS.keys, nil ] },
      fragments_to_next_medal: { type: :integer },
      medal_progress_percent: { type: :integer }
    }
  }.freeze

  ACHIEVEMENTS = {
    type: :object,
    required: %w[seasons_played medals_earned fragments medal_counts seasons reward_badges],
    properties: {
      seasons_played: { type: :integer },
      medals_earned: { type: :integer },
      fragments: { type: :integer },
      medal_counts: {
        type: :object,
        required: SeasonParticipation::MEDAL_TIERS.keys,
        properties: SeasonParticipation::MEDAL_TIERS.keys.index_with { { type: :integer } }
      },
      seasons: { type: :array, items: SEASON_MEDAL },
      reward_badges: {
        type: :array,
        items: {
          type: :object,
          required: %w[id name],
          properties: {
            id: { type: :integer },
            name: nullable_string,
            icon: nullable_string,
            earned_at: { type: :string, format: "date-time", nullable: true }
          }
        }
      }
    }
  }.freeze
end
