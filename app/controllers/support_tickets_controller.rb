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
    @ticket = current_user.support_tickets.new(ticket_params)
    @ticket.status = "open"
    @ticket.support_messages.build(
      user: current_user,
      body: params.dig(:support_ticket, :body).to_s,
      from_admin: false
    )

    if @ticket.save
      Analytics.track(user: current_user, event: "support_ticket_created", properties: { category: @ticket.category, source: @ticket.source })
      redirect_to support_ticket_path(@ticket), notice: t("flashes.support.created")
    else
      render :new, status: :unprocessable_entity
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
