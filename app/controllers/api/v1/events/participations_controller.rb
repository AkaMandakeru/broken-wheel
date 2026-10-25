# frozen_string_literal: true

module Api
  module V1
    module Events
      # RSVP to an event, link the workout that was the result, or drop out.
      # Same rules and analytics as the web, via ::Events::ParticipationRecorder.
      # Every success answers with the refreshed event.
      class ParticipationsController < Api::V1::EventsController
        idempotent only: :create

        before_action :set_event

        def create
          result = recorder.rsvp(participation_params)

          case result.status
          when :already_going then render_error :conflict, "already_going"
          when :created
            track_event "api.event.rsvp", event_id: @event.id, completed: result.participation.completed?
            render_event_detail @event.reload, status: :created
          else render_invalid result.participation
          end
        end

        def update
          result = recorder.update(participation_params)
          return render_invalid(result.participation) unless result.success?

          track_event "api.event.result_linked", event_id: @event.id, workout_id: result.participation.workout_id
          render_event_detail @event.reload
        rescue ActiveRecord::RecordNotFound
          render_error :not_found, "not_going"
        end

        def destroy
          recorder.cancel
          track_event "api.event.rsvp_cancelled", event_id: @event.id
          head :no_content
        end

        private

        def set_event
          @event = Event.find(params[:event_id])
        end

        def recorder
          ::Events::ParticipationRecorder.new(@event, current_user)
        end

        def participation_params
          return {} if params[:participation].blank?

          params.expect(participation: ::Events::ParticipationRecorder::ATTRIBUTES).to_h.symbolize_keys
        end
      end
    end
  end
end
