class CreateTimelinePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :timeline_posts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :challenge, null: false, foreign_key: true
      t.references :workout, foreign_key: true
      t.text :content
      t.jsonb :metadata

      t.timestamps
    end
  end
end
