class CreateSupportTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :support_tickets do |t|
      t.references :user, null: false, foreign_key: true
      t.string :subject
      t.string :category, default: "general", null: false
      t.string :source, default: "general", null: false
      t.string :status, default: "open", null: false
      t.datetime :last_message_at
      t.integer :support_messages_count, default: 0, null: false

      t.timestamps
    end

    add_index :support_tickets, :status
    add_index :support_tickets, :last_message_at

    create_table :support_messages do |t|
      t.references :support_ticket, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.boolean :from_admin, default: false, null: false

      t.timestamps
    end
  end
end
