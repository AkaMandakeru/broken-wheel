# frozen_string_literal: true

module Api
  # Structured events (Rails 8.1 `Rails.event`) for every API action that
  # matters, carrying who, which build and which request, so a log line can be
  # traced back to a device. See config/initializers/event_reporting.rb.
  #
  #   track_event "api.workout.created", workout_id: workout.id
  module Events
    extend ActiveSupport::Concern

    included do
      before_action :set_event_context
    end

    private

    def set_event_context
      Rails.event.set_context(
        request_id: request.request_id,
        app_version: request.headers["X-App-Version"],
        platform: request.headers["X-Platform"]
      )
    end

    def track_event(name, **payload)
      Rails.event.notify(name, user_id: current_user&.id, **payload)
    end
  end
end
