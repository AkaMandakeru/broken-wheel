class CreateBadges < ActiveRecord::Migration[8.1]
  def change
    create_table :badges do |t|
      t.string :name
      t.string :icon
      t.text :description
      t.string :badge_type

      t.timestamps
    end
  end
end
