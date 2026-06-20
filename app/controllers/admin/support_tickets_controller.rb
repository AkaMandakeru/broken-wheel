# frozen_string_literal: true

module Admin
  class SupportTicketsController < BaseController
    before_action :set_ticket, only: [ :show, :update ]

    def index
      @status = params[:status].presence_in(SupportTicket::STATUSES)
      scope = SupportTicket.includes(:user).recent_first
      scope = scope.where(status: @status) if @status
      @tickets = scope
      @open_count = SupportTicket.open_tickets.count
    end

    def show
      @messages = @ticket.support_messages.includes(:user).order(:created_at)
    end

    def update
      new_status = params.dig(:support_ticket, :status).presence_in(SupportTicket::STATUSES)
      @ticket.update(status: new_status) if new_status
      redirect_to admin_support_ticket_path(@ticket), notice: t("admin.flashes.support.updated")
    end

    private

    def set_ticket
      @ticket = SupportTicket.find(params[:id])
    end
  end
end
