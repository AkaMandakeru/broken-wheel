# frozen_string_literal: true

class SupportTicketsController < ApplicationController
  before_action :authenticate_user!

  def index
    @tickets = current_user.support_tickets.recent_first
  end

  def new
    @ticket = current_user.support_tickets.new(source: source_param, category: default_category)
  end

  def show
    @ticket = current_user.support_tickets.find(params[:id])
    @messages = @ticket.support_messages.includes(:user).order(:created_at)
  end

  def create
    @ticket = SupportDesk.open_ticket(current_user, **ticket_params.to_h.symbolize_keys, body: params.dig(:support_ticket, :body))

    if @ticket.persisted?
      redirect_to support_ticket_path(@ticket), notice: t("flashes.support.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def ticket_params
    params.require(:support_ticket).permit(:subject, :category, :source)
  end

  def source_param
    params[:source].presence_in(SupportTicket::SOURCES) || "general"
  end

  def default_category
    source_param == "integrations" ? "support" : "general"
  end
end
