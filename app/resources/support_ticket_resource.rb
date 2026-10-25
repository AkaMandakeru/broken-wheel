# frozen_string_literal: true

class SupportTicketResource < ApplicationResource
  attributes :id, :subject, :category, :source, :status

  attribute(:messages_count, &:support_messages_count)
  attribute(:created_at) { |ticket| ticket.created_at.iso8601 }
  attribute(:last_message_at) { |ticket| (ticket.last_message_at || ticket.created_at).iso8601 }
end
