# frozen_string_literal: true

class AddAnnouncementToSeasons < ActiveRecord::Migration[8.1]
  def up
    # Stamped when the "new season" announcement goes out, so activating a
    # season twice — or a retried job — never notifies everyone again.
    add_column :seasons, :announced_at, :datetime

    # Seasons that were already running before announcements existed must not
    # suddenly announce themselves as new.
    execute <<~SQL.squish
      UPDATE seasons SET announced_at = COALESCE(starts_at, created_at)
      WHERE status IN ('active', 'ended')
    SQL
  end

  def down
    remove_column :seasons, :announced_at
  end
end
