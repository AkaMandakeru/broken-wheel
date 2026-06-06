class AddParticipationsCountToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :event_participations_count, :integer, default: 0, null: false

    execute <<~SQL.squish
      UPDATE events SET event_participations_count = (
        SELECT COUNT(*) FROM event_participations
        WHERE event_participations.event_id = events.id
      )
    SQL
  end

  def down
    remove_column :events, :event_participations_count
  end
end
