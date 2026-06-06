class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string :title, null: false
      t.text :description
      t.string :sport
      t.datetime :event_date
      t.string :location
      t.decimal :distance_km
      t.string :status, default: "upcoming", null: false

      t.timestamps
    end

    add_index :events, :event_date
    add_index :events, :status
  end
end
