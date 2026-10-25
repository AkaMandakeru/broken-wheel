# frozen_string_literal: true

class EventParticipationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_event

  # RSVP ("I'll be there") and/or record a result in one step.
  # Workout params are optional: an empty submit just marks the user as going.
  def create
    result = recorder.rsvp(participation_params)

    case result.status
    when :already_going then redirect_to event_path(@event), notice: t("flashes.events.already_going")
    when :created then redirect_to event_path(@event), notice: rsvp_notice(result.participation)
    else redirect_to event_path(@event), alert: participation_error(result.participation)
    end
  end

  # Attach or change the workout (result) on an existing participation.
  def update
    result = recorder.update(participation_params)

    if result.success?
      redirect_to event_path(@event), notice: t("flashes.events.workout_linked")
    else
      redirect_to event_path(@event), alert: participation_error(result.participation)
    end
  end

  def destroy
    recorder.cancel
    redirect_to event_path(@event), notice: t("flashes.events.removed")
  end

  private

  def set_event
    @event = Event.find(params[:event_id])
  end

  def recorder
    Events::ParticipationRecorder.new(@event, current_user)
  end

  def participation_params
    return {} unless params.key?(:event_participation)

    params.require(:event_participation).permit(*Events::ParticipationRecorder::ATTRIBUTES)
  end

  def rsvp_notice(participation)
    participation.completed? ? t("flashes.events.recorded") : t("flashes.events.going")
  end

  def participation_error(participation)
    participation.errors.full_messages.to_sentence.presence || t("flashes.events.record_failed")
  end
end
