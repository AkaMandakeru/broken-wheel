class CreateChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :challenges do |t|
      t.string :title
      t.text :description
      t.string :challenge_type
      t.string :sport
      t.decimal :target_value
      t.string :target_unit
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :status

      t.timestamps
    end
  end
end
