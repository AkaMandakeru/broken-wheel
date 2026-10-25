# frozen_string_literal: true

module Events
  # "I'll be there" and "here's my result" for an event, shared by the web's
  # EventParticipationsController and Api::V1::Events::ParticipationsController.
  #
  #   result = Events::ParticipationRecorder.new(event, current_user).rsvp(workout_id: 12)
  #   result.status         # :created, :already_going or :invalid
  #   result.participation
  class ParticipationRecorder
    ATTRIBUTES = %i[workout_id bib_number notes selected_distance_km].freeze

    Result = Data.define(:status, :participation) do
      def success? = %i[created updated].include?(status)
    end

    attr_reader :event, :user

    def initialize(event, user)
      @event = event
      @user = user
    end

    def current
      user.event_participations.find_by(event: event)
    end

    # RSVP and/or record a result in one step. With no attributes it just marks
    # the user as going.
    def rsvp(attributes = {})
      participation = user.event_participations.find_or_initialize_by(event: event)
      return Result.new(status: :already_going, participation: participation) if participation.persisted?

      participation.assign_attributes(attributes)
      save(participation, :created)
    rescue ActiveRecord::RecordNotUnique
      Result.new(status: :already_going, participation: current)
    end

    # Attach or change the workout (result) on an existing participation.
    # Raises RecordNotFound when the user isn't going.
    def update(attributes)
      participation = user.event_participations.find_by!(event: event)
      participation.assign_attributes(attributes)
      save(participation, :updated)
    end

    def cancel
      current&.destroy
    end

    private

    def save(participation, status)
      return Result.new(status: :invalid, participation: participation) unless participation.save

      track_recorded(participation)
      Result.new(status: status, participation: participation)
    end

    def track_recorded(participation)
      Analytics.track(
        user: user,
        event: "event_participation_recorded",
        properties: { event_id: event.id, sport: event.sport, workout_id: participation.workout_id, completed: participation.completed? }
      )
    end
  end
end
