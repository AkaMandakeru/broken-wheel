class CreateStravaTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :strava_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :access_token
      t.string :refresh_token
      t.integer :expires_at
      t.bigint :athlete_id
      t.string :scope

      t.timestamps
    end
  end
end
