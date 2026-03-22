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

ActiveRecord::Schema[8.1].define(version: 2026_03_22_182250) do
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
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["challenge_id"], name: "index_challenge_participations_on_challenge_id"
    t.index ["invite_code"], name: "index_challenge_participations_on_invite_code", unique: true
    t.index ["invited_by_id"], name: "index_challenge_participations_on_invited_by_id"
    t.index ["user_id"], name: "index_challenge_participations_on_user_id"
  end

  create_table "challenges", force: :cascade do |t|
    t.string "challenge_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at"
    t.string "sport"
    t.datetime "starts_at"
    t.string "status"
    t.string "target_unit"
    t.decimal "target_value"
    t.string "title"
    t.datetime "updated_at", null: false
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

  create_table "users", force: :cascade do |t|
    t.string "address"
    t.string "blood_type"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "document"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.datetime "locked_at"
    t.string "nickname"
    t.string "phone"
    t.jsonb "preferences", default: {}
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.jsonb "sports", default: []
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "workouts", force: :cascade do |t|
    t.bigint "challenge_participation_id"
    t.datetime "created_at", null: false
    t.decimal "distance_km"
    t.integer "duration_minutes"
    t.string "external_id"
    t.string "provider"
    t.jsonb "raw_data"
    t.string "sport"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.date "workout_date"
    t.index ["challenge_participation_id"], name: "index_workouts_on_challenge_participation_id"
    t.index ["user_id"], name: "index_workouts_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "challenge_participations", "challenges"
  add_foreign_key "challenge_participations", "users"
  add_foreign_key "challenge_participations", "users", column: "invited_by_id"
  add_foreign_key "club_memberships", "clubs"
  add_foreign_key "club_memberships", "users"
  add_foreign_key "clubs", "users", column: "created_by_id"
  add_foreign_key "timeline_post_comments", "timeline_posts"
  add_foreign_key "timeline_post_comments", "users"
  add_foreign_key "timeline_posts", "challenges"
  add_foreign_key "timeline_posts", "users"
  add_foreign_key "timeline_posts", "workouts"
  add_foreign_key "user_badges", "badges"
  add_foreign_key "user_badges", "challenges"
  add_foreign_key "user_badges", "users"
  add_foreign_key "workouts", "challenge_participations"
  add_foreign_key "workouts", "users"
end
