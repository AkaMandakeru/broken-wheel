# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_20_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "analytics_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.jsonb "properties", default: {}
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["created_at"], name: "index_analytics_events_on_created_at"
    t.index ["event_name"], name: "index_analytics_events_on_event_name"
    t.index ["user_id"], name: "index_analytics_events_on_user_id"
  end

  create_table "badges", force: :cascade do |t|
    t.string "badge_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon"
    t.string "name"
    t.integer "points", default: 0, null: false
    t.decimal "threshold_distance", precision: 10, scale: 2
    t.decimal "threshold_value", precision: 10, scale: 2
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "challenge_participations", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "invite_code"
    t.bigint "invited_by_id"
    t.integer "points", default: 0, null: false
    t.decimal "progress_value", precision: 10, scale: 2, default: "0.0"
    t.jsonb "requirement_progress", default: {}, null: false
    t.bigint "season_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["challenge_id"], name: "index_challenge_participations_on_challenge_id"
    t.index ["invite_code"], name: "index_challenge_participations_on_invite_code", unique: true
    t.index ["invited_by_id"], name: "index_challenge_participations_on_invited_by_id"
    t.index ["season_id"], name: "index_challenge_participations_on_season_id"
    t.index ["user_id", "challenge_id", "season_id"], name: "idx_challenge_participations_user_challenge_season", unique: true, where: "(season_id IS NOT NULL)"
    t.index ["user_id", "challenge_id"], name: "idx_challenge_participations_user_challenge_standalone", unique: true, where: "(season_id IS NULL)"
    t.index ["user_id"], name: "index_challenge_participations_on_user_id"
  end

  create_table "challenge_requirements", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.string "comparator", default: "gte", null: false
    t.datetime "created_at", null: false
    t.string "label_key"
    t.string "metric", null: false
    t.jsonb "options", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.decimal "target", precision: 12, scale: 2, null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["challenge_id", "position"], name: "index_challenge_requirements_on_challenge_id_and_position"
    t.index ["challenge_id"], name: "index_challenge_requirements_on_challenge_id"
  end

  create_table "challenges", force: :cascade do |t|
    t.string "challenge_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at"
    t.string "key"
    t.string "sport"
    t.datetime "starts_at"
    t.string "status"
    t.string "target_unit"
    t.decimal "target_value"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_challenges_on_key", unique: true
  end

  create_table "club_memberships", force: :cascade do |t|
    t.bigint "club_id", null: false
    t.datetime "created_at", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["club_id"], name: "index_club_memberships_on_club_id"
    t.index ["user_id"], name: "index_club_memberships_on_user_id"
  end

  create_table "clubs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.text "description"
    t.integer "member_count", default: 0, null: false
    t.string "name"
    t.string "sport"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_clubs_on_created_by_id"
  end

  create_table "coin_transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "reason", null: false
    t.string "reason_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "reason_key"], name: "index_coin_transactions_on_user_id_and_reason_key", unique: true
    t.index ["user_id"], name: "index_coin_transactions_on_user_id"
  end

  create_table "cosmetics", force: :cascade do |t|
    t.boolean "animated", default: false, null: false
    t.datetime "created_at", null: false
    t.string "css_class"
    t.string "icon"
    t.string "key", null: false
    t.string "kind", null: false
    t.string "name"
    t.string "rarity", default: "common", null: false
    t.boolean "renderable", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_cosmetics_on_key", unique: true
    t.index ["kind"], name: "index_cosmetics_on_kind"
  end

  create_table "daily_challenge_assignments", force: :cascade do |t|
    t.date "challenge_date", null: false
    t.integer "coin_awarded", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "daily_challenge_template_id", null: false
    t.bigint "season_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "xp_awarded", default: 0, null: false
    t.index ["daily_challenge_template_id"], name: "idx_daily_assignments_template"
    t.index ["season_id", "challenge_date"], name: "idx_on_season_id_challenge_date_dfeac51cb3"
    t.index ["season_id"], name: "index_daily_challenge_assignments_on_season_id"
    t.index ["user_id", "challenge_date", "daily_challenge_template_id"], name: "idx_daily_assignments_unique", unique: true
    t.index ["user_id"], name: "index_daily_challenge_assignments_on_user_id"
  end

  create_table "daily_challenge_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "coin_reward", default: 25, null: false
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "metric", null: false
    t.jsonb "options", default: {}, null: false
    t.boolean "requires_start_time", default: false, null: false
    t.bigint "season_id"
    t.string "sport"
    t.decimal "target", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.integer "weight", default: 1, null: false
    t.integer "xp_reward", default: 50, null: false
    t.index ["season_id", "key"], name: "index_daily_challenge_templates_on_season_id_and_key", unique: true
    t.index ["season_id"], name: "index_daily_challenge_templates_on_season_id"
  end

  create_table "event_participations", force: :cascade do |t|
    t.string "bib_number"
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.text "notes"
    t.decimal "selected_distance_km"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_id"
    t.index ["event_id"], name: "index_event_participations_on_event_id"
    t.index ["user_id", "event_id"], name: "index_event_participations_on_user_id_and_event_id", unique: true
    t.index ["user_id"], name: "index_event_participations_on_user_id"
    t.index ["workout_id"], name: "index_event_participations_on_workout_id"
  end

  create_table "events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "distance_km"
    t.jsonb "distances", default: [], null: false
    t.datetime "event_date"
    t.integer "event_participations_count", default: 0, null: false
    t.string "location"
    t.bigint "season_id"
    t.string "sport"
    t.string "status", default: "upcoming", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["event_date"], name: "index_events_on_event_date"
    t.index ["season_id"], name: "index_events_on_season_id"
    t.index ["status"], name: "index_events_on_status"
  end

  create_table "feature_flags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "disabled_at"
    t.string "disabled_by"
    t.boolean "enabled", default: true, null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_feature_flags_on_key", unique: true
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth_key", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "p256dh_key", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "season_activities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "season_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["season_id", "created_at"], name: "index_season_activities_on_season_id_and_created_at"
    t.index ["season_id"], name: "index_season_activities_on_season_id"
    t.index ["user_id"], name: "index_season_activities_on_user_id"
  end

  create_table "season_challenge_completions", force: :cascade do |t|
    t.datetime "claimed_at"
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.bigint "season_challenge_id", null: false
    t.bigint "season_participation_id", null: false
    t.datetime "updated_at", null: false
    t.integer "xp_awarded", default: 0, null: false
    t.index ["season_challenge_id"], name: "index_season_challenge_completions_on_season_challenge_id"
    t.index ["season_participation_id", "claimed_at"], name: "idx_season_completions_claim_state"
    t.index ["season_participation_id", "season_challenge_id"], name: "idx_season_completions_unique", unique: true
    t.index ["season_participation_id"], name: "index_season_challenge_completions_on_season_participation_id"
  end

  create_table "season_challenges", force: :cascade do |t|
    t.string "category", default: "standard", null: false
    t.bigint "challenge_id", null: false
    t.integer "coin_reward", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at"
    t.integer "fragment_reward", default: 0, null: false
    t.boolean "hidden", default: false, null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false, null: false
    t.bigint "season_id", null: false
    t.datetime "starts_at"
    t.integer "unlock_level", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "week_index"
    t.integer "xp_reward", default: 0, null: false
    t.index ["challenge_id"], name: "index_season_challenges_on_challenge_id"
    t.index ["season_id", "category"], name: "index_season_challenges_on_season_id_and_category"
    t.index ["season_id", "challenge_id"], name: "index_season_challenges_on_season_id_and_challenge_id", unique: true
    t.index ["season_id"], name: "index_season_challenges_on_season_id"
  end

  create_table "season_community_goals", force: :cascade do |t|
    t.decimal "base_target_value", precision: 14, scale: 2
    t.datetime "computed_at"
    t.datetime "created_at", null: false
    t.decimal "current_value", precision: 14, scale: 2, default: "0.0", null: false
    t.string "key", null: false
    t.integer "max_tiers"
    t.string "metric", null: false
    t.decimal "per_participant", precision: 10, scale: 2
    t.bigint "season_id", null: false
    t.string "target_mode", default: "fixed", null: false
    t.decimal "target_value", precision: 14, scale: 2, null: false
    t.integer "tier", default: 1, null: false
    t.integer "tier_coin_reward", default: 0, null: false
    t.decimal "tier_started_value", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "tier_target_value", precision: 14, scale: 2
    t.datetime "updated_at", null: false
    t.index ["season_id", "key"], name: "index_season_community_goals_on_season_id_and_key", unique: true
    t.index ["season_id"], name: "index_season_community_goals_on_season_id"
  end

  create_table "season_community_milestones", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "percent", null: false
    t.datetime "reached_at"
    t.bigint "season_community_goal_id", null: false
    t.bigint "season_reward_id"
    t.decimal "threshold", precision: 14, scale: 2, null: false
    t.integer "tier", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["season_community_goal_id", "tier", "percent"], name: "idx_community_milestones_unique", unique: true
    t.index ["season_community_goal_id"], name: "idx_community_milestones_goal"
    t.index ["season_reward_id"], name: "index_season_community_milestones_on_season_reward_id"
  end

  create_table "season_objective_completions", force: :cascade do |t|
    t.datetime "completed_at", null: false
    t.datetime "created_at", null: false
    t.bigint "season_objective_id", null: false
    t.bigint "season_participation_id", null: false
    t.datetime "updated_at", null: false
    t.integer "xp_awarded", default: 0, null: false
    t.index ["season_objective_id"], name: "index_season_objective_completions_on_season_objective_id"
    t.index ["season_participation_id", "season_objective_id"], name: "idx_season_objective_completions_unique", unique: true
    t.index ["season_participation_id"], name: "index_season_objective_completions_on_season_participation_id"
  end

  create_table "season_objectives", force: :cascade do |t|
    t.integer "coin_reward", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "fragment_reward", default: 0, null: false
    t.string "icon"
    t.string "kind", null: false
    t.string "metric"
    t.string "name"
    t.jsonb "options", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.boolean "required", default: false, null: false
    t.bigint "season_id", null: false
    t.integer "target", default: 1, null: false
    t.string "track", default: "standard", null: false
    t.datetime "updated_at", null: false
    t.integer "xp_reward", default: 0, null: false
    t.index ["season_id", "track"], name: "index_season_objectives_on_season_id_and_track"
    t.index ["season_id"], name: "index_season_objectives_on_season_id"
  end

  create_table "season_participations", force: :cascade do |t|
    t.integer "activities_count", default: 0, null: false
    t.integer "best_5k_seconds"
    t.integer "coins_earned", default: 0, null: false
    t.integer "completion_percent", default: 0, null: false
    t.datetime "created_at", null: false
    t.decimal "elevation_gain_m", precision: 10, scale: 1, default: "0.0", null: false
    t.datetime "last_recalculated_at"
    t.integer "level", default: 1, null: false
    t.integer "longest_streak_days", default: 0, null: false
    t.integer "medal_fragments", default: 0, null: false
    t.boolean "premium", default: false, null: false
    t.datetime "premium_granted_at"
    t.bigint "season_id", null: false
    t.decimal "total_distance_km", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "xp", default: 0, null: false
    t.jsonb "xp_breakdown", default: {}, null: false
    t.index ["season_id", "activities_count"], name: "index_season_participations_on_season_id_and_activities_count"
    t.index ["season_id", "best_5k_seconds"], name: "index_season_participations_on_season_id_and_best_5k_seconds"
    t.index ["season_id", "elevation_gain_m"], name: "index_season_participations_on_season_id_and_elevation_gain_m"
    t.index ["season_id", "longest_streak_days"], name: "idx_on_season_id_longest_streak_days_a9b4b574a4"
    t.index ["season_id", "total_distance_km"], name: "index_season_participations_on_season_id_and_total_distance_km"
    t.index ["season_id", "user_id"], name: "index_season_participations_on_season_id_and_user_id", unique: true
    t.index ["season_id", "xp"], name: "index_season_participations_on_season_id_and_xp"
    t.index ["season_id"], name: "index_season_participations_on_season_id"
    t.index ["user_id"], name: "index_season_participations_on_user_id"
  end

  create_table "season_reward_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "granted_at", null: false
    t.bigint "season_participation_id", null: false
    t.bigint "season_reward_id", null: false
    t.datetime "updated_at", null: false
    t.index ["season_participation_id", "season_reward_id"], name: "idx_season_reward_grants_unique", unique: true
    t.index ["season_participation_id"], name: "index_season_reward_grants_on_season_participation_id"
    t.index ["season_reward_id"], name: "index_season_reward_grants_on_season_reward_id"
  end

  create_table "season_rewards", force: :cascade do |t|
    t.integer "coins", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "level"
    t.string "name"
    t.jsonb "payload", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.string "reward_key", null: false
    t.string "reward_type", null: false
    t.bigint "season_id", null: false
    t.string "track", default: "free", null: false
    t.string "unlock_kind", default: "level", null: false
    t.integer "unlock_value"
    t.datetime "updated_at", null: false
    t.index ["season_id", "level"], name: "index_season_rewards_on_season_id_and_level"
    t.index ["season_id", "unlock_kind", "unlock_value"], name: "index_season_rewards_on_unlock"
    t.index ["season_id"], name: "index_season_rewards_on_season_id"
  end

  create_table "seasons", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "curve_exponent", precision: 4, scale: 2, default: "1.5", null: false
    t.text "description"
    t.datetime "ends_at"
    t.datetime "finalized_at"
    t.string "key"
    t.jsonb "level_curve", default: [], null: false
    t.integer "max_level", default: 5, null: false
    t.string "name", null: false
    t.string "slogan"
    t.datetime "starts_at"
    t.string "status", default: "upcoming", null: false
    t.string "theme", default: "default", null: false
    t.string "time_zone", default: "America/Sao_Paulo", null: false
    t.integer "top_level_xp"
    t.datetime "updated_at", null: false
    t.decimal "xp_multiplier", precision: 5, scale: 2, default: "1.0", null: false
    t.index ["key"], name: "index_seasons_on_key", unique: true
    t.index ["status"], name: "index_seasons_on_status"
  end

  create_table "strava_tokens", force: :cascade do |t|
    t.string "access_token"
    t.bigint "athlete_id"
    t.datetime "created_at", null: false
    t.integer "expires_at"
    t.string "refresh_token"
    t.string "scope"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_strava_tokens_on_user_id"
  end

  create_table "support_messages", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.boolean "from_admin", default: false, null: false
    t.bigint "support_ticket_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["support_ticket_id"], name: "index_support_messages_on_support_ticket_id"
    t.index ["user_id"], name: "index_support_messages_on_user_id"
  end

  create_table "support_tickets", force: :cascade do |t|
    t.string "category", default: "general", null: false
    t.datetime "created_at", null: false
    t.datetime "last_message_at"
    t.string "source", default: "general", null: false
    t.string "status", default: "open", null: false
    t.string "subject"
    t.integer "support_messages_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["last_message_at"], name: "index_support_tickets_on_last_message_at"
    t.index ["status"], name: "index_support_tickets_on_status"
    t.index ["user_id"], name: "index_support_tickets_on_user_id"
  end

  create_table "timeline_post_comments", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "timeline_post_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["timeline_post_id"], name: "index_timeline_post_comments_on_timeline_post_id"
    t.index ["user_id"], name: "index_timeline_post_comments_on_user_id"
  end

  create_table "timeline_posts", force: :cascade do |t|
    t.bigint "challenge_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.jsonb "metadata"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "workout_id"
    t.index ["challenge_id"], name: "index_timeline_posts_on_challenge_id"
    t.index ["user_id"], name: "index_timeline_posts_on_user_id"
    t.index ["workout_id"], name: "index_timeline_posts_on_workout_id"
  end

  create_table "user_badges", force: :cascade do |t|
    t.bigint "badge_id", null: false
    t.bigint "challenge_id"
    t.datetime "created_at", null: false
    t.datetime "earned_at"
    t.decimal "earned_value", precision: 10, scale: 4
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["badge_id"], name: "index_user_badges_on_badge_id"
    t.index ["challenge_id"], name: "index_user_badges_on_challenge_id"
    t.index ["user_id"], name: "index_user_badges_on_user_id"
  end

  create_table "user_cosmetics", force: :cascade do |t|
    t.bigint "cosmetic_id", null: false
    t.datetime "created_at", null: false
    t.string "source"
    t.datetime "unlocked_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["cosmetic_id"], name: "index_user_cosmetics_on_cosmetic_id"
    t.index ["user_id", "cosmetic_id"], name: "index_user_cosmetics_on_user_id_and_cosmetic_id", unique: true
    t.index ["user_id"], name: "index_user_cosmetics_on_user_id"
  end

  create_table "user_xp_boosts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.decimal "multiplier", precision: 4, scale: 2, default: "2.0", null: false
    t.string "source_key", null: false
    t.datetime "starts_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "source_key"], name: "index_user_xp_boosts_on_user_id_and_source_key", unique: true
    t.index ["user_id"], name: "index_user_xp_boosts_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "address"
    t.boolean "admin", default: false, null: false
    t.string "blood_type"
    t.integer "coins", default: 0, null: false
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "document"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.jsonb "equipped_cosmetics", default: {}, null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.integer "lifetime_xp", default: 0, null: false
    t.datetime "locked_at"
    t.string "nickname"
    t.string "phone"
    t.jsonb "preferences", default: {}
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.jsonb "sports", default: []
    t.string "theme"
    t.string "title"
    t.jsonb "titles", default: [], null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.jsonb "unlocked_themes", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "workouts", force: :cascade do |t|
    t.integer "calories"
    t.bigint "challenge_participation_id"
    t.datetime "created_at", null: false
    t.decimal "distance_km"
    t.integer "duration_minutes"
    t.integer "elapsed_time_seconds"
    t.decimal "elevation_gain_m", precision: 8, scale: 1
    t.string "external_id"
    t.integer "moving_time_seconds"
    t.string "provider"
    t.jsonb "raw_data"
    t.string "route_signature"
    t.string "sport"
    t.integer "start_minute_of_day"
    t.boolean "start_time_known", default: false, null: false
    t.datetime "started_at"
    t.datetime "started_at_local"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.date "workout_date"
    t.index ["challenge_participation_id"], name: "index_workouts_on_challenge_participation_id"
    t.index ["user_id", "provider", "external_id"], name: "index_workouts_on_user_provider_external_id", unique: true, where: "((provider IS NOT NULL) AND (external_id IS NOT NULL))"
    t.index ["user_id", "started_at_local"], name: "index_workouts_on_user_id_and_started_at_local"
    t.index ["user_id", "workout_date"], name: "index_workouts_on_user_id_and_workout_date"
    t.index ["user_id"], name: "index_workouts_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "analytics_events", "users"
  add_foreign_key "challenge_participations", "challenges"
  add_foreign_key "challenge_participations", "seasons"
  add_foreign_key "challenge_participations", "users"
  add_foreign_key "challenge_participations", "users", column: "invited_by_id"
  add_foreign_key "challenge_requirements", "challenges"
  add_foreign_key "club_memberships", "clubs"
  add_foreign_key "club_memberships", "users"
  add_foreign_key "clubs", "users", column: "created_by_id"
  add_foreign_key "coin_transactions", "users"
  add_foreign_key "daily_challenge_assignments", "daily_challenge_templates"
  add_foreign_key "daily_challenge_assignments", "seasons"
  add_foreign_key "daily_challenge_assignments", "users"
  add_foreign_key "daily_challenge_templates", "seasons"
  add_foreign_key "event_participations", "events"
  add_foreign_key "event_participations", "users"
  add_foreign_key "event_participations", "workouts"
  add_foreign_key "events", "seasons"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "season_activities", "seasons"
  add_foreign_key "season_activities", "users"
  add_foreign_key "season_challenge_completions", "season_challenges"
  add_foreign_key "season_challenge_completions", "season_participations"
  add_foreign_key "season_challenges", "challenges"
  add_foreign_key "season_challenges", "seasons"
  add_foreign_key "season_community_goals", "seasons"
  add_foreign_key "season_community_milestones", "season_community_goals"
  add_foreign_key "season_community_milestones", "season_rewards"
  add_foreign_key "season_objective_completions", "season_objectives"
  add_foreign_key "season_objective_completions", "season_participations"
  add_foreign_key "season_objectives", "seasons"
  add_foreign_key "season_participations", "seasons"
  add_foreign_key "season_participations", "users"
  add_foreign_key "season_reward_grants", "season_participations"
  add_foreign_key "season_reward_grants", "season_rewards"
  add_foreign_key "season_rewards", "seasons"
  add_foreign_key "strava_tokens", "users"
  add_foreign_key "support_messages", "support_tickets"
  add_foreign_key "support_messages", "users"
  add_foreign_key "support_tickets", "users"
  add_foreign_key "timeline_post_comments", "timeline_posts"
  add_foreign_key "timeline_post_comments", "users"
  add_foreign_key "timeline_posts", "challenges"
  add_foreign_key "timeline_posts", "users"
  add_foreign_key "timeline_posts", "workouts"
  add_foreign_key "user_badges", "badges"
  add_foreign_key "user_badges", "challenges"
  add_foreign_key "user_badges", "users"
  add_foreign_key "user_cosmetics", "cosmetics"
  add_foreign_key "user_cosmetics", "users"
  add_foreign_key "user_xp_boosts", "users"
  add_foreign_key "workouts", "challenge_participations"
  add_foreign_key "workouts", "users"
end
