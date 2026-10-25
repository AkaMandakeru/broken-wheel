# frozen_string_literal: true

module Api
  module V1
    module Support
      # The player's conversations with the team. Opening a ticket and
      # replying go through SupportDesk, like the web.
      class TicketsController < BaseController
        requires_feature :support
        idempotent only: :create

        def index
          # Ordered by latest activity, which changes as messages arrive, so
          # the list isn't cursor-paginated; a player has a handful of tickets.
          render_collection SupportTicketResource, current_user.support_tickets.recent_first
        end

        def show
          render_resource SupportTicketDetailResource, current_user.support_tickets.find(params[:id])
        end

        def create
          attributes = params.expect(ticket: [ :subject, :category, :source, :body ]).to_h.symbolize_keys
          ticket = SupportDesk.open_ticket(current_user, **attributes)
          return render_ticket_invalid(ticket) unless ticket.persisted?

          track_event "api.support_ticket.created", ticket_id: ticket.id, category: ticket.category
          render_resource SupportTicketDetailResource, ticket, status: :created
        end

        private

        # The first message's errors show up on the ticket as `support_messages`;
        # the app knows the field as `body`.
        def render_ticket_invalid(ticket)
          fields = ticket.errors.to_hash(true).transform_values { |messages| messages.map(&:to_s) }
          body_errors = ticket.support_messages.first&.errors&.full_messages_for(:body)
          fields.delete(:support_messages)
          fields[:body] = body_errors if body_errors.present?
          render_error :unprocessable_content, "validation_failed", fields: fields
        end
      end
    end
  end
end
