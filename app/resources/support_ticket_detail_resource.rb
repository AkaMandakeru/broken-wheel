# frozen_string_literal: true

class SupportTicketDetailResource < SupportTicketResource
  attribute :messages do |ticket|
    SupportMessageResource.new(ticket.support_messages.order(:created_at, :id)).serializable_hash
  end
end
