# frozen_string_literal: true

# Global on/off switches for the app's user-facing features.
#
# A feature with no row here is enabled. That way the catalogue can grow without
# a backfill, and a fresh database has everything switched on — which is the
# behaviour you want if this table is ever empty or unreachable.
class CreateFeatureFlags < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_flags do |t|
      t.string   :key, null: false
      t.boolean  :enabled, default: true, null: false
      t.datetime :disabled_at
      t.string   :disabled_by
      t.timestamps
    end

    add_index :feature_flags, :key, unique: true
  end
end
