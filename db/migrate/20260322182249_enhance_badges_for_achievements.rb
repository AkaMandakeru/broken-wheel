class EnhanceBadgesForAchievements < ActiveRecord::Migration[8.1]
  def change
    add_column :badges, :points, :integer, default: 0, null: false
    add_column :badges, :title, :string
    add_column :badges, :threshold_value, :decimal, precision: 10, scale: 2
    add_column :badges, :threshold_distance, :decimal, precision: 10, scale: 2
  end
end
