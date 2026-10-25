# frozen_string_literal: true

module Api
  module V1
    class EventsController < BaseController
      PAST_LIMIT = 50
      # The same cap the web's "link a workout" picker uses.
      WORKOUT_CHOICES = 50

      requires_feature :events

      def index
        upcoming = Event.upcoming.by_date.with_attached_image.to_a
        past = Event.where(status: "completed").order(event_date: :desc).limit(PAST_LIMIT).with_attached_image.to_a
        participations = current_user.event_participations.includes(:workout)
                                     .where(event_id: (upcoming + past).map(&:id)).index_by(&:event_id)

        render_data({
          upcoming: EventResource.new(upcoming, params: resource_params.merge(participations: participations)).serializable_hash,
          past: EventResource.new(past, params: resource_params.merge(participations: participations)).serializable_hash
        })
      end

      def show
        event = Event.find(params[:id])
        render_event_detail(event)
      end

      private

      # Shared with Events::ParticipationsController, which answers with the
      # refreshed event page.
      def render_event_detail(event, status: :ok)
        participation = current_user.event_participations.includes(:workout).find_by(event_id: event.id)
        workouts = current_user.workouts.order(workout_date: :desc, id: :desc).limit(WORKOUT_CHOICES) if participation.nil? || participation.going?

        render_resource EventDetailResource, event, status: status, participation: participation, available_workouts: workouts.to_a
      end
    end
  end
end
