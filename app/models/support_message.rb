class SupportMessage < ApplicationRecord
  belongs_to :support_ticket, counter_cache: true
  belongs_to :user

  validates :body, presence: true

  after_create :touch_ticket

  private

  # Keep the ticket's status and ordering in sync with the latest message.
  def touch_ticket
    support_ticket.update_columns(
      status: from_admin ? "answered" : "open",
      last_message_at: created_at,
      updated_at: Time.current
    )
  end
end
