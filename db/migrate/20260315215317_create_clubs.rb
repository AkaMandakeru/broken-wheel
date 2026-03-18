class CreateClubs < ActiveRecord::Migration[8.1]
  def change
    create_table :clubs do |t|
      t.string :name
      t.text :description
      t.string :sport
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.integer :member_count, default: 0, null: false

      t.timestamps
    end
  end
end
