class AddDistancesToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :distances, :jsonb, default: [], null: false
    add_column :event_participations, :selected_distance_km, :decimal
  end
end
