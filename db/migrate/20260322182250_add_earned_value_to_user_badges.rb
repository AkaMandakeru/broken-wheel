class AddEarnedValueToUserBadges < ActiveRecord::Migration[8.1]
  def change
    add_column :user_badges, :earned_value, :decimal, precision: 10, scale: 4
  end
end
