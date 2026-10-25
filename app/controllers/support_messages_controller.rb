# frozen_string_literal: true

class SupportMessagesController < ApplicationController
  before_action :authenticate_user!

  def create
    @ticket = current_user.support_tickets.find(params[:support_ticket_id])
    message = SupportDesk.reply(@ticket, current_user, body: params.dig(:support_message, :body))

    if message.persisted?
      redirect_to support_ticket_path(@ticket), notice: t("flashes.support.message_sent")
    else
      redirect_to support_ticket_path(@ticket), alert: t("flashes.support.message_failed")
    end
  end
end
