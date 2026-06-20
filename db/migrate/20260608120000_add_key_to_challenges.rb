class AddKeyToChallenges < ActiveRecord::Migration[8.1]
  def change
    add_column :challenges, :key, :string
    add_index :challenges, :key, unique: true
  end
end
