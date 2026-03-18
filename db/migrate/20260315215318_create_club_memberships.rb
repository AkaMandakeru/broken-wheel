class CreateClubMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :club_memberships do |t|
      t.references :club, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role

      t.timestamps
    end
  end
end
