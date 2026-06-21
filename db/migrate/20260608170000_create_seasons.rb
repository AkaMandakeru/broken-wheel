class CreateSeasons < ActiveRecord::Migration[8.1]
  def change
    create_table :seasons do |t|
      t.string :key
      t.string :name, null: false
      t.text :description
      t.string :theme, default: "default", null: false
      t.string :status, default: "upcoming", null: false
      t.datetime :starts_at
      t.datetime :ends_at
      t.decimal :xp_multiplier, precision: 5, scale: 2, default: "1.0", null: false

      t.timestamps
    end
    add_index :seasons, :key, unique: true
    add_index :seasons, :status

    create_table :season_challenges do |t|
      t.references :season, null: false, foreign_key: true
      t.references :challenge, null: false, foreign_key: true
      t.integer :position, default: 0, null: false
      t.boolean :required, default: false, null: false
      t.integer :xp_reward, default: 0, null: false

      t.timestamps
    end
    add_index :season_challenges, [ :season_id, :challenge_id ], unique: true

    create_table :season_participations do |t|
      t.references :season, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :xp, default: 0, null: false
      t.integer :level, default: 1, null: false
      t.jsonb :xp_breakdown, default: {}, null: false
      t.datetime :last_recalculated_at

      t.timestamps
    end
    add_index :season_participations, [ :season_id, :user_id ], unique: true

    create_table :season_challenge_completions do |t|
      t.references :season_participation, null: false, foreign_key: true
      t.references :season_challenge, null: false, foreign_key: true
      t.integer :xp_awarded, default: 0, null: false
      t.datetime :completed_at, null: false

      t.timestamps
    end
    add_index :season_challenge_completions, [ :season_participation_id, :season_challenge_id ],
              unique: true, name: "idx_season_completions_unique"

    create_table :season_rewards do |t|
      t.references :season, null: false, foreign_key: true
      t.integer :level, null: false
      t.string :reward_type, null: false
      t.string :reward_key, null: false
      t.string :name

      t.timestamps
    end
    add_index :season_rewards, [ :season_id, :level ]

    create_table :season_reward_grants do |t|
      t.references :season_participation, null: false, foreign_key: true
      t.references :season_reward, null: false, foreign_key: true
      t.datetime :granted_at, null: false

      t.timestamps
    end
    add_index :season_reward_grants, [ :season_participation_id, :season_reward_id ],
              unique: true, name: "idx_season_reward_grants_unique"

    create_table :season_activities do |t|
      t.references :season, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end
    add_index :season_activities, [ :season_id, :created_at ]

    add_column :users, :lifetime_xp, :integer, default: 0, null: false
    add_column :users, :unlocked_themes, :jsonb, default: [], null: false
    add_column :users, :theme, :string
    add_reference :events, :season, foreign_key: true, null: true
  end
end
