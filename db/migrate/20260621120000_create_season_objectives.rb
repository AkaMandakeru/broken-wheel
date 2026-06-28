class CreateSeasonObjectives < ActiveRecord::Migration[8.1]
  def change
    create_table :season_objectives do |t|
      t.references :season, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :xp_reward, default: 0, null: false
      t.integer :target, default: 1, null: false
      t.integer :position, default: 0, null: false
      t.boolean :required, default: false, null: false
      t.string :name

      t.timestamps
    end

    create_table :season_objective_completions do |t|
      t.references :season_participation, null: false, foreign_key: true
      t.references :season_objective, null: false, foreign_key: true
      t.integer :xp_awarded, default: 0, null: false
      t.datetime :completed_at, null: false

      t.timestamps
    end
    add_index :season_objective_completions, [ :season_participation_id, :season_objective_id ],
              unique: true, name: "idx_season_objective_completions_unique"
  end
end
