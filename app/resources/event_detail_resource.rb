# frozen_string_literal: true

# One event's page: who's going, how many chose each distance, and — when the
# viewer is going but hasn't linked a result — the workouts they could link.
# `params[:participation]` is the viewer's own; `params[:available_workouts]`
# the candidates.
class EventDetailResource < EventResource
  attribute :my_participation do |_event|
    participation = params[:participation]
    participation && EventParticipationResource.new(participation).serializable_hash
  end

  attribute :distance_counts do |event|
    event.participation_counts_by_distance.sort.map { |distance, count| { distance_km: distance, count: count } }
  end

  attribute :participants do |event|
    event.event_participations.includes(:workout, user: { avatar_attachment: :blob }).order(:created_at, :id).map do |participation|
      { user: UserSummaryResource.new(participation.user).serializable_hash,
        participation: EventParticipationResource.new(participation).serializable_hash.except("notes", "bib_number") }
    end
  end

  attribute :available_workouts do |_event|
    AttachedWorkoutResource.new(params[:available_workouts] || []).serializable_hash
  end
end
