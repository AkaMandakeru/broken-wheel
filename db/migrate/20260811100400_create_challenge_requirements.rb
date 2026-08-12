# frozen_string_literal: true

# A challenge is a set of requirements, all of which must be met. Season weeklies
# read "run 15 km AND complete 4 workouts AND finish one run over 6 km", which a
# single target_value/target_unit pair cannot express.
class CreateChallengeRequirements < ActiveRecord::Migration[8.1]
  def change
    create_table :challenge_requirements do |t|
      t.references :challenge, null: false, foreign_key: true
      t.integer :position, default: 0, null: false
      t.string  :metric, null: false
      t.string  :comparator, default: "gte", null: false
      t.decimal :target, precision: 12, scale: 2, null: false
      t.string  :unit
      t.jsonb   :options, default: {}, null: false
      t.string  :label_key
      t.timestamps
    end

    add_index :challenge_requirements, [ :challenge_id, :position ]

    add_column :challenge_participations, :requirement_progress, :jsonb, default: {}, null: false

    # Existing challenges become single-requirement challenges so the new
    # evaluator is the only code path from here on.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          INSERT INTO challenge_requirements (challenge_id, position, metric, comparator, target, unit, options, created_at, updated_at)
          SELECT id,
                 0,
                 CASE target_unit
                   WHEN 'km'    THEN 'distance_km'
                   WHEN 'times' THEN 'activity_count'
                   WHEN 'hours' THEN 'duration_hours'
                   ELSE 'distance_km'
                 END,
                 'gte',
                 COALESCE(target_value, 1),
                 target_unit,
                 '{}'::jsonb,
                 NOW(),
                 NOW()
          FROM challenges
          WHERE target_value IS NOT NULL
        SQL
      end
    end
  end
end
