# frozen_string_literal: true

class CreateDailyChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_challenge_templates do |t|
      t.references :season, foreign_key: true
      t.string  :key, null: false
      t.string  :metric, null: false
      t.decimal :target, precision: 12, scale: 2, null: false
      t.jsonb   :options, default: {}, null: false
      t.string  :sport
      t.integer :xp_reward, default: 50, null: false
      t.integer :coin_reward, default: 25, null: false
      t.integer :weight, default: 1, null: false
      t.boolean :active, default: true, null: false

      # Templates that read the clock are withheld from users whose workouts
      # carry no start time — otherwise they draw an unwinnable daily.
      t.boolean :requires_start_time, default: false, null: false
      t.timestamps
    end

    add_index :daily_challenge_templates, [ :season_id, :key ], unique: true

    create_table :daily_challenge_assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :season, null: false, foreign_key: true
      t.references :daily_challenge_template, null: false, foreign_key: true, index: { name: "idx_daily_assignments_template" }
      t.date     :challenge_date, null: false
      t.datetime :completed_at
      t.integer  :xp_awarded, default: 0, null: false
      t.integer  :coin_awarded, default: 0, null: false
      t.timestamps
    end

    add_index :daily_challenge_assignments,
              [ :user_id, :challenge_date, :daily_challenge_template_id ],
              unique: true, name: "idx_daily_assignments_unique"
    add_index :daily_challenge_assignments, [ :season_id, :challenge_date ]
  end
end
