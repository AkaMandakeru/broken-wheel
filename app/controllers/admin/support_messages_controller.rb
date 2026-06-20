# frozen_string_literal: true

module Admin
  class SupportMessagesController < BaseController
    def create
      @ticket = SupportTicket.find(params[:support_ticket_id])
      message = @ticket.support_messages.new(
        user: current_user,
        body: params.dig(:support_message, :body).to_s,
        from_admin: true
      )

      if message.save
        redirect_to admin_support_ticket_path(@ticket), notice: t("admin.flashes.support.replied")
      else
        redirect_to admin_support_ticket_path(@ticket), alert: t("admin.flashes.support.reply_failed")
      end
    end
  end
end
