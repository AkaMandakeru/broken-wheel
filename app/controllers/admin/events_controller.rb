# frozen_string_literal: true

module Admin
  class EventsController < BaseController
    before_action :set_event, only: [ :show, :edit, :update, :destroy ]

    def index
      @events = Event.order(event_date: :desc)
    end

    def show
      @participations = @event.event_participations.includes(:user, :workout)
      @distance_counts = @event.participation_counts_by_distance
    end

    def new
      @event = Event.new(status: "upcoming")
    end

    def edit
    end

    def create
      @event = Event.new(event_params)

      if @event.save
        redirect_to admin_event_path(@event), notice: t("admin.flashes.events.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @event.update(event_params)
        redirect_to admin_event_path(@event), notice: t("admin.flashes.events.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @event.destroy
      redirect_to admin_events_path, notice: t("admin.flashes.events.destroyed")
    end

    private

    def set_event
      @event = Event.find(params[:id])
    end

    def event_params
      permitted = params.require(:event).permit(
        :title, :description, :sport, :event_date, :location,
        :status, :image, :custom_distances, distances: []
      )

      # Merge the checkbox selections with any free-text custom distances; the
      # Event#distances= setter normalises, de-dupes and sorts the result.
      custom = permitted.delete(:custom_distances)
      permitted[:distances] = Array(permitted[:distances]) + [ custom ].compact

      permitted
    end
  end
end
