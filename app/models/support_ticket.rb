class SupportTicket < ApplicationRecord
  belongs_to :user
  has_many :support_messages, dependent: :destroy

  CATEGORIES = %w[general support suggestion bug].freeze
  SOURCES    = %w[general integrations challenges events workouts achievements profile].freeze
  STATUSES   = %w[open answered closed].freeze

  validates :subject, presence: true, length: { maximum: 200 }
  validates :category, inclusion: { in: CATEGORIES }
  validates :source, inclusion: { in: SOURCES }
  validates :status, inclusion: { in: STATUSES }

  scope :open_tickets, -> { where(status: "open") }
  scope :recent_first, -> { order(Arel.sql("COALESCE(last_message_at, created_at) DESC")) }

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end
end
