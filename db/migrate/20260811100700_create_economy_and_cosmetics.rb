# frozen_string_literal: true

class CreateEconomyAndCosmetics < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :coins, :integer, default: 0, null: false
    add_column :users, :equipped_cosmetics, :jsonb, default: {}, null: false

    create_table :coin_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount, null: false # signed: credits positive, spends negative
      t.string  :reason, null: false
      t.string  :reason_key, null: false
      t.jsonb   :metadata, default: {}, null: false
      t.timestamps
    end

    # The idempotency gate: granting the same reward twice is a no-op rather
    # than free currency.
    add_index :coin_transactions, [ :user_id, :reason_key ], unique: true

    create_table :cosmetics do |t|
      t.string  :key, null: false
      t.string  :kind, null: false
      t.string  :name
      t.string  :rarity, default: "common", null: false
      t.string  :css_class
      t.string  :icon
      t.boolean :animated, default: false, null: false

      # False for items we can award but not yet draw (trails, outfits). They
      # sit in the collection until their art exists.
      t.boolean :renderable, default: true, null: false
      t.timestamps
    end

    add_index :cosmetics, :key, unique: true
    add_index :cosmetics, :kind

    create_table :user_cosmetics do |t|
      t.references :user, null: false, foreign_key: true
      t.references :cosmetic, null: false, foreign_key: true
      t.string   :source
      t.datetime :unlocked_at, null: false
      t.timestamps
    end

    add_index :user_cosmetics, [ :user_id, :cosmetic_id ], unique: true

    create_table :user_xp_boosts do |t|
      t.references :user, null: false, foreign_key: true
      t.decimal  :multiplier, precision: 4, scale: 2, default: 2.0, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string   :source_key, null: false
      t.timestamps
    end

    add_index :user_xp_boosts, [ :user_id, :source_key ], unique: true
  end
end
