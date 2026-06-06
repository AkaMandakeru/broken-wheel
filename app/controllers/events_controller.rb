# frozen_string_literal: true

class EventsController < ApplicationController
  before_action :authenticate_user!, except: [ :index, :show ]
  before_action :set_event, only: [ :show ]

  def index
    @upcoming_events = Event.upcoming.by_date
    @past_events = Event.where(status: "completed").order(event_date: :desc)
  end

  def show
    @participations = @event.event_participations.includes(:user, :workout)
    @distance_counts = @event.participation_counts_by_distance

    if user_signed_in?
      @participation = current_user.event_participations.find_by(event_id: @event.id)
      if @participation.nil? || @participation.going?
        @available_workouts = current_user.workouts.order(workout_date: :desc).limit(50)
      end
    end
  end

  private

  def set_event
    @event = Event.find(params[:id])
  end
end
