# frozen_string_literal: true

class EventParticipationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_event

  # RSVP ("I'll be there") and/or record a result in one step.
  # Workout params are optional: an empty submit just marks the user as going.
  def create
    participation = current_user.event_participations.find_or_initialize_by(event: @event)

    if participation.persisted?
      return redirect_to event_path(@event), notice: t("flashes.events.already_going")
    end

    participation.assign_attributes(participation_params)

    if participation.save
      track_recorded(participation)
      redirect_to event_path(@event), notice: rsvp_notice(participation)
    else
      redirect_to event_path(@event), alert: participation_error(participation)
    end
  end

  # Attach or change the workout (result) on an existing participation.
  def update
    participation = current_user.event_participations.find_by!(event: @event)

    if participation.update(participation_params)
      track_recorded(participation)
      redirect_to event_path(@event), notice: t("flashes.events.workout_linked")
    else
      redirect_to event_path(@event), alert: participation_error(participation)
    end
  end

  def destroy
    current_user.event_participations.find_by(event: @event)&.destroy
    redirect_to event_path(@event), notice: t("flashes.events.removed")
  end

  private

  def set_event
    @event = Event.find(params[:event_id])
  end

  def participation_params
    return {} unless params.key?(:event_participation)

    params.require(:event_participation).permit(:workout_id, :bib_number, :notes, :selected_distance_km)
  end

  def rsvp_notice(participation)
    participation.completed? ? t("flashes.events.recorded") : t("flashes.events.going")
  end

  def participation_error(participation)
    participation.errors.full_messages.to_sentence.presence || t("flashes.events.record_failed")
  end

  def track_recorded(participation)
    Analytics.track(
      user: current_user,
      event: "event_participation_recorded",
      properties: { event_id: @event.id, sport: @event.sport, workout_id: participation.workout_id, completed: participation.completed? }
    )
  end
end
