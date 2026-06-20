# frozen_string_literal: true

class SupportMessagesController < ApplicationController
  before_action :authenticate_user!

  def create
    @ticket = current_user.support_tickets.find(params[:support_ticket_id])
    message = @ticket.support_messages.new(
      user: current_user,
      body: params.dig(:support_message, :body).to_s,
      from_admin: false
    )

    if message.save
      redirect_to support_ticket_path(@ticket), notice: t("flashes.support.message_sent")
    else
      redirect_to support_ticket_path(@ticket), alert: t("flashes.support.message_failed")
    end
  end
end
