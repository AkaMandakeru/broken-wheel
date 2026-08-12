# frozen_string_literal: true

class CreateSeasonCommunityGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :season_community_goals do |t|
      t.references :season, null: false, foreign_key: true
      t.string  :key, null: false
      t.string  :metric, null: false
      t.decimal :target_value, precision: 14, scale: 2, null: false
      t.decimal :current_value, precision: 14, scale: 2, default: 0, null: false

      # "fixed" uses target_value as given; "per_participant" scales the goal to
      # the size of the community so it stays reachable.
      t.string  :target_mode, default: "fixed", null: false
      t.decimal :per_participant, precision: 10, scale: 2
      t.datetime :computed_at
      t.timestamps
    end

    add_index :season_community_goals, [ :season_id, :key ], unique: true

    create_table :season_community_milestones do |t|
      t.references :season_community_goal, null: false, foreign_key: true, index: { name: "idx_community_milestones_goal" }
      t.integer  :percent, null: false
      t.decimal  :threshold, precision: 14, scale: 2, null: false
      t.references :season_reward, foreign_key: true
      t.datetime :reached_at
      t.timestamps
    end

    add_index :season_community_milestones, [ :season_community_goal_id, :percent ],
              unique: true, name: "idx_community_milestones_unique"
  end
end
