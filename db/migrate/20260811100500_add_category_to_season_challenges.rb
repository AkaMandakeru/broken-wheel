# frozen_string_literal: true

class AddCategoryToSeasonChallenges < ActiveRecord::Migration[8.1]
  def change
    # daily | weekly | monthly | elite | hidden | standard
    add_column :season_challenges, :category, :string, default: "standard", null: false

    # Elite content gates on battle pass level; 0 means always available.
    add_column :season_challenges, :unlock_level, :integer, default: 0, null: false

    # Secret achievements stay off the challenge list until discovered.
    add_column :season_challenges, :hidden, :boolean, default: false, null: false

    add_column :season_challenges, :coin_reward, :integer, default: 0, null: false
    add_column :season_challenges, :fragment_reward, :integer, default: 0, null: false
    add_column :season_challenges, :week_index, :integer

    add_index :season_challenges, [ :season_id, :category ]
  end
end
