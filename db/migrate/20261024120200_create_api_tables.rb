# Tables the mobile API needs (docs/MOBILE_API_PLAN.md §6–§8, §10).
class CreateApiTables < ActiveRecord::Migration[8.1]
  def change
    # One row per refresh token. Refreshing revokes the row and creates the next
    # one in the same family, so presenting a revoked token again is detectable
    # (token theft) and revokes the whole family.
    create_table :api_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :refresh_token_digest, null: false
      t.uuid :family_id, null: false
      t.string :device_name
      t.string :platform
      t.string :app_version
      t.datetime :last_used_at
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.string :revoked_reason
      t.timestamps

      t.index :refresh_token_digest, unique: true
      t.index :family_id
      t.index [ :user_id, :revoked_at ]
    end

    # The first response to a POST carrying an Idempotency-Key, replayed on retry.
    create_table :idempotency_keys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :key, null: false
      t.string :request_digest, null: false
      t.integer :response_status
      t.jsonb :response_body
      t.timestamps

      t.index [ :user_id, :key ], unique: true
      t.index :created_at
    end

    # Native push tokens (Expo Push Service).
    create_table :device_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :token, null: false
      t.string :app_version
      t.string :locale
      t.datetime :last_seen_at
      t.timestamps

      t.index :token, unique: true
    end

    # Player reports of user-generated content (App Store guideline 1.2).
    create_table :content_reports do |t|
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.references :reportable, polymorphic: true, null: false
      t.references :reported_user, foreign_key: { to_table: :users }
      t.string :reason, null: false
      t.text :details
      t.string :status, null: false, default: "open"
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.timestamps

      t.index [ :reporter_id, :reportable_type, :reportable_id ], unique: true, name: "index_content_reports_once_per_reporter"
      t.index :status
    end

    create_table :user_blocks do |t|
      t.references :blocker, null: false, foreign_key: { to_table: :users }
      t.references :blocked, null: false, foreign_key: { to_table: :users }
      t.timestamps

      t.index [ :blocker_id, :blocked_id ], unique: true
    end
  end
end
