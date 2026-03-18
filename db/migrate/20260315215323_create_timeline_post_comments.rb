class CreateTimelinePostComments < ActiveRecord::Migration[8.1]
  def change
    create_table :timeline_post_comments do |t|
      t.references :timeline_post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content

      t.timestamps
    end
  end
end
