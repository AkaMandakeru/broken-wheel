class CreateAnalyticsEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_events do |t|
      t.references :user, foreign_key: true
      t.string :event_name, null: false
      t.jsonb :properties, default: {}

      t.timestamps
    end

    add_index :analytics_events, :event_name
    add_index :analytics_events, :created_at
  end
end
