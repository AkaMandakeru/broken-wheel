class CreateWorkouts < ActiveRecord::Migration[8.1]
  def change
    create_table :workouts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :challenge_participation, foreign_key: true
      t.string :provider
      t.string :external_id
      t.string :sport
      t.decimal :distance_km
      t.integer :duration_minutes
      t.date :workout_date
      t.jsonb :raw_data

      t.timestamps
    end
  end
end
