# frozen_string_literal: true

# OpenAPI schemas for challenges, timeline, clubs, events, support and
# moderation (spec/requests/api/v1). Kept beside the specs rather than in
# swagger_helper.rb, which is shared.
module SocialSchemas
  NULLABLE_STRING = { type: :string, nullable: true }.freeze
  NULLABLE_NUMBER = { type: :number, nullable: true }.freeze
  NULLABLE_DATE_TIME = { type: :string, format: "date-time", nullable: true }.freeze
  DATE_TIME = { type: :string, format: "date-time" }.freeze
  IMAGE = { "$ref" => "#/components/schemas/image" }.freeze
  USER = { "$ref" => "#/components/schemas/user_summary" }.freeze

  def self.data(schema) = { type: :object, required: [ "data" ], properties: { data: schema } }

  def self.page(item) = {
    type: :object, required: %w[data meta],
    properties: { data: { type: :array, items: item }, meta: { "$ref" => "#/components/schemas/page_meta" } }
  }

  def self.list(item) = { type: :object, required: [ "data" ], properties: { data: { type: :array, items: item } } }

  # --- Challenges ------------------------------------------------------------

  ATTACHED_WORKOUT = {
    type: :object, nullable: true,
    required: %w[id sport workout_date distance_km duration_minutes],
    properties: {
      id: { type: :integer },
      sport: NULLABLE_STRING,
      workout_date: { type: :string, format: :date, nullable: true },
      distance_km: NULLABLE_NUMBER,
      duration_minutes: { type: :integer, nullable: true }
    }
  }.freeze

  CHALLENGE_REQUIREMENT = {
    type: :object,
    required: %w[id metric comparator label target unit],
    properties: {
      id: { type: :integer },
      metric: { type: :string, example: "distance_km" },
      comparator: { type: :string, enum: ChallengeRequirement::COMPARATORS },
      label: { type: :string, example: "Run 50 km" },
      target: { type: :number },
      unit: NULLABLE_STRING
    }
  }.freeze

  CHALLENGE_PARTICIPATION = {
    type: :object, nullable: true,
    required: %w[id season_id progress_value percent_complete completed completed_at joined_at requirements],
    properties: {
      id: { type: :integer },
      season_id: { type: :integer, nullable: true, description: "Null for a challenge joined outside any season" },
      progress_value: { type: :number },
      percent_complete: { type: :integer, minimum: 0, maximum: 100 },
      completed: { type: :boolean },
      completed_at: NULLABLE_DATE_TIME,
      joined_at: DATE_TIME,
      requirements: {
        type: :array,
        items: {
          type: :object, required: %w[requirement_id value percent met],
          properties: {
            requirement_id: { type: :integer }, value: NULLABLE_NUMBER,
            percent: { type: :integer }, met: { type: :boolean }
          }
        }
      }
    }
  }.freeze

  CHALLENGE = {
    type: :object,
    required: %w[id title description challenge_type sport status target_value target_unit starts_at ends_at image requirements my_participation],
    properties: {
      id: { type: :integer },
      key: NULLABLE_STRING,
      title: { type: :string },
      description: NULLABLE_STRING,
      challenge_type: { type: :string, nullable: true, enum: Challenge::CHALLENGE_TYPES + [ nil ] },
      sport: NULLABLE_STRING,
      status: NULLABLE_STRING,
      target_value: NULLABLE_NUMBER,
      target_unit: NULLABLE_STRING,
      starts_at: NULLABLE_DATE_TIME,
      ends_at: NULLABLE_DATE_TIME,
      image: IMAGE,
      requirements: { type: :array, items: CHALLENGE_REQUIREMENT },
      my_participation: CHALLENGE_PARTICIPATION
    }
  }.freeze

  CHALLENGE_DETAIL = CHALLENGE.merge(
    required: CHALLENGE[:required] + %w[season ranking],
    properties: CHALLENGE[:properties].merge(
      season: {
        type: :object, nullable: true, required: %w[id name],
        description: "The active season the progress and ranking are read in; null for a standalone challenge",
        properties: { id: { type: :integer }, name: { type: :string } }
      },
      ranking: {
        type: :array,
        items: {
          type: :object,
          required: %w[rank user progress_value percent_complete completed me],
          properties: {
            rank: { type: :integer }, user: USER, progress_value: { type: :number },
            percent_complete: { type: :integer }, completed: { type: :boolean }, me: { type: :boolean }
          }
        }
      }
    )
  ).freeze

  CHALLENGE_INVITE = {
    type: :object, required: %w[invite_code url title message],
    properties: {
      invite_code: { type: :string }, url: { type: :string, description: "Web link to the challenge (a universal link)" },
      title: { type: :string }, message: { type: :string, description: "Suggested text for the share sheet" }
    }
  }.freeze

  # --- Timeline --------------------------------------------------------------

  TIMELINE_COMMENT = {
    type: :object, required: %w[id timeline_post_id content created_at user mine],
    properties: {
      id: { type: :integer }, timeline_post_id: { type: :integer }, content: { type: :string },
      created_at: DATE_TIME, user: USER, mine: { type: :boolean }
    }
  }.freeze

  TIMELINE_POST = {
    type: :object, required: %w[id challenge_id content created_at user mine workout images comments],
    properties: {
      id: { type: :integer },
      challenge_id: { type: :integer },
      content: NULLABLE_STRING,
      created_at: DATE_TIME,
      user: USER,
      mine: { type: :boolean },
      workout: ATTACHED_WORKOUT,
      images: { type: :array, items: { type: :object, additionalProperties: { type: :string }, description: "original, thumb and large URLs" } },
      comments: { type: :array, items: TIMELINE_COMMENT }
    }
  }.freeze

  # --- Clubs -----------------------------------------------------------------

  CLUB = {
    type: :object, required: %w[id name description sport member_count created_at created_by member],
    properties: {
      id: { type: :integer }, name: { type: :string }, description: NULLABLE_STRING,
      sport: { type: :string, nullable: true, enum: Club::SPORTS + [ nil ] },
      member_count: { type: :integer }, created_at: DATE_TIME, created_by: USER,
      member: { type: :boolean, description: "Whether the viewer belongs to the club" }
    }
  }.freeze

  CLUB_DETAIL = CLUB.merge(
    required: CLUB[:required] + %w[my_membership members],
    properties: CLUB[:properties].merge(
      my_membership: {
        type: :object, nullable: true, required: %w[role joined_at],
        properties: { role: { type: :string, enum: %w[admin member] }, joined_at: DATE_TIME }
      },
      members: {
        type: :array,
        items: {
          type: :object, required: %w[role joined_at user],
          properties: { role: { type: :string, enum: %w[admin member] }, joined_at: DATE_TIME, user: USER }
        }
      }
    )
  ).freeze

  # --- Events ----------------------------------------------------------------

  EVENT_PARTICIPATION = {
    type: :object, nullable: true,
    required: %w[id event_id status workout_id selected_distance_km workout pace_min_per_km],
    properties: {
      id: { type: :integer },
      event_id: { type: :integer },
      status: { type: :string, enum: %w[going completed], description: "completed once a workout is linked" },
      bib_number: NULLABLE_STRING,
      notes: NULLABLE_STRING,
      workout_id: { type: :integer, nullable: true },
      selected_distance_km: NULLABLE_NUMBER,
      workout: ATTACHED_WORKOUT,
      pace_min_per_km: NULLABLE_NUMBER
    }
  }.freeze

  EVENT = {
    type: :object,
    required: %w[id title description sport status location season_id event_date distance_km distances participants_count image my_participation],
    properties: {
      id: { type: :integer },
      title: { type: :string },
      description: NULLABLE_STRING,
      sport: NULLABLE_STRING,
      status: { type: :string, enum: Event::STATUSES },
      location: NULLABLE_STRING,
      season_id: { type: :integer, nullable: true },
      event_date: NULLABLE_DATE_TIME,
      distance_km: NULLABLE_NUMBER,
      distances: { type: :array, items: { type: :number }, description: "Distances (km) to pick from; empty when there is no choice" },
      participants_count: { type: :integer },
      image: IMAGE,
      my_participation: EVENT_PARTICIPATION
    }
  }.freeze

  EVENT_DETAIL = EVENT.merge(
    required: EVENT[:required] + %w[distance_counts participants available_workouts],
    properties: EVENT[:properties].merge(
      distance_counts: {
        type: :array,
        items: { type: :object, required: %w[distance_km count], properties: { distance_km: { type: :number }, count: { type: :integer } } }
      },
      participants: {
        type: :array,
        items: { type: :object, required: %w[user participation], properties: { user: USER, participation: EVENT_PARTICIPATION } }
      },
      available_workouts: {
        type: :array, items: ATTACHED_WORKOUT,
        description: "The viewer's recent workouts to link as a result; empty once one is linked"
      }
    )
  ).freeze

  EVENT_LISTS = {
    type: :object, required: [ "data" ],
    properties: {
      data: {
        type: :object, required: %w[upcoming past],
        properties: { upcoming: { type: :array, items: EVENT }, past: { type: :array, items: EVENT } }
      }
    }
  }.freeze

  PARTICIPATION_INPUT = {
    type: :object,
    properties: {
      participation: {
        type: :object,
        properties: {
          workout_id: { type: :integer, nullable: true }, bib_number: { type: :string },
          notes: { type: :string }, selected_distance_km: { type: :number, description: "Required when the event offers distances" }
        }
      }
    }
  }.freeze

  # --- Support ---------------------------------------------------------------

  SUPPORT_MESSAGE = {
    type: :object, required: %w[id body from_admin created_at],
    properties: { id: { type: :integer }, body: { type: :string }, from_admin: { type: :boolean }, created_at: DATE_TIME }
  }.freeze

  SUPPORT_TICKET = {
    type: :object, required: %w[id subject category source status messages_count created_at last_message_at],
    properties: {
      id: { type: :integer },
      subject: { type: :string },
      category: { type: :string, enum: SupportTicket::CATEGORIES },
      source: { type: :string, enum: SupportTicket::SOURCES },
      status: { type: :string, enum: SupportTicket::STATUSES },
      messages_count: { type: :integer },
      created_at: DATE_TIME,
      last_message_at: DATE_TIME
    }
  }.freeze

  SUPPORT_TICKET_DETAIL = SUPPORT_TICKET.merge(
    required: SUPPORT_TICKET[:required] + [ "messages" ],
    properties: SUPPORT_TICKET[:properties].merge(messages: { type: :array, items: SUPPORT_MESSAGE })
  ).freeze

  # --- Moderation ------------------------------------------------------------

  CONTENT_REPORT = {
    type: :object, required: %w[id reportable_type reportable_id reason status created_at],
    properties: {
      id: { type: :integer },
      reportable_type: { type: :string, enum: ContentReport::REPORTABLE_TYPES.keys },
      reportable_id: { type: :integer },
      reason: { type: :string, enum: ContentReport::REASONS },
      details: NULLABLE_STRING,
      status: { type: :string, enum: ContentReport::STATUSES },
      created_at: DATE_TIME
    }
  }.freeze

  USER_BLOCK = {
    type: :object, required: %w[blocked_at user],
    properties: { blocked_at: DATE_TIME, user: USER }
  }.freeze
end
