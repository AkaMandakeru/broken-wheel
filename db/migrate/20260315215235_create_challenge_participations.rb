class CreateChallengeParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :challenge_participations do |t|
      t.references :challenge, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :invite_code
      t.references :invited_by, foreign_key: { to_table: :users }
      t.integer :points, default: 0, null: false
      t.decimal :progress_value, default: 0, precision: 10, scale: 2
      t.datetime :completed_at

      t.timestamps
    end
    add_index :challenge_participations, :invite_code, unique: true
  end
end
