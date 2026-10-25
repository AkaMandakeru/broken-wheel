# frozen_string_literal: true

module Api
  module V1
    # The player's training log, and adding a workout by hand. XP is credited
    # asynchronously (Workout#after_create_commit → SeasonRecalcJob), so a new
    # workout answers `xp_pending` and the app refetches the season shortly.
    class WorkoutsController < BaseController
      requires_feature :workouts
      idempotent only: :create

      # Validation errors name the fields the app sent, not the model's.
      API_FIELDS = { duration_minutes: :duration_seconds, start_time_input: :start_time }.freeze

      def index
        workouts, meta = paginate(current_user.workouts.order(workout_date: :desc, id: :desc))
        meta = meta.merge(totals) if params[:cursor].blank?
        render_collection WorkoutResource, workouts, meta: meta
      end

      def create
        workout = Workouts::ManualEntry.new(current_user, manual_entry_attributes).call
        return render_workout_errors(workout) unless workout.persisted?

        track_event "api.workout.created", workout_id: workout.id, provider: workout.provider
        render_data WorkoutResource.new(workout, params: resource_params).serializable_hash,
                    status: :created, meta: { xp_pending: Season.active.exists? }
      end

      private

      def totals
        { workout_count: current_user.workouts.count,
          unique_days: current_user.workouts.distinct.count(:workout_date) }
      end

      # Maps the API's units onto the inputs the web form uses, so Workout's
      # callbacks do the normalising.
      def manual_entry_attributes
        attrs = params.expect(workout: [ :sport, :workout_date, :start_time, :distance_km, :duration_seconds ])
        { sport: attrs[:sport], workout_date: attrs[:workout_date], start_time_input: attrs[:start_time],
          distance_km_input: attrs[:distance_km], duration_seconds_input: attrs[:duration_seconds] }
      end

      def render_workout_errors(workout)
        fields = workout.errors.to_hash(true).to_h do |attribute, messages|
          [ API_FIELDS.fetch(attribute, attribute), messages ]
        end
        render_error :unprocessable_content, "validation_failed", fields: fields
      end
    end
  end
end
