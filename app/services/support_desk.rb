# frozen_string_literal: true

# A player's side of a support conversation — opening a ticket with its first
# message and replying to it — for the web's SupportTicketsController /
# SupportMessagesController and the API's Support::* controllers.
module SupportDesk
  module_function

  # The ticket, saved unless invalid (check `persisted?`).
  def open_ticket(user, body: nil, subject: nil, category: nil, source: nil)
    ticket = user.support_tickets.new(subject: subject, category: category.presence || "general",
                                      source: source.presence || "general", status: "open")
    ticket.support_messages.build(user: user, body: body.to_s, from_admin: false)

    if ticket.save
      Analytics.track(user: user, event: "support_ticket_created", properties: { category: ticket.category, source: ticket.source })
    end
    ticket
  end

  # The message, saved unless invalid.
  def reply(ticket, user, body:)
    message = ticket.support_messages.new(user: user, body: body.to_s, from_admin: false)
    message.save
    message
  end
end
