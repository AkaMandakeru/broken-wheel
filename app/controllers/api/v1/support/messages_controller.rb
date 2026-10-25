# frozen_string_literal: true

module Api
  module V1
    module Support
      class MessagesController < BaseController
        requires_feature :support
        idempotent only: :create

        def create
          ticket = current_user.support_tickets.find(params[:ticket_id])
          message = SupportDesk.reply(ticket, current_user, body: params.expect(message: [ :body ])[:body])
          return render_invalid(message) unless message.persisted?

          track_event "api.support_message.created", ticket_id: ticket.id
          render_resource SupportMessageResource, message, status: :created
        end
      end
    end
  end
end
