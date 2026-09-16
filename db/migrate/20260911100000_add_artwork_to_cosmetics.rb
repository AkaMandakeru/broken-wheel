# frozen_string_literal: true

# Banners and avatar frames are pictures an operator uploads, not CSS classes,
# so cosmetics grows an ordering column and picks up an Active Storage
# attachment. `position` gives the locker and the admin list a stable order
# that is not "whatever id the row happened to get".
class AddArtworkToCosmetics < ActiveRecord::Migration[8.1]
  def change
    add_column :cosmetics, :position, :integer, default: 0, null: false
    add_index :cosmetics, [ :kind, :position ]
  end
end
