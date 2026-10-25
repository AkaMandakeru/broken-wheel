# frozen_string_literal: true

# An event in the list. `params[:participations]` is { event_id => the
# viewer's EventParticipation }.
class EventResource < ApplicationResource
  attributes :id, :title, :description, :sport, :status, :location, :season_id

  attribute(:event_date) { |event| event.event_date&.iso8601 }
  attribute(:distance_km) { |event| event.distance_km&.to_f }
  attribute(:distances) { |event| event.distances.map(&:to_f) }
  attribute(:participants_count, &:event_participations_count)
  attribute(:image) { |event| ImageUrls.urls(event.image, :card, :hero) }

  attribute :my_participation do |event|
    participation = params[:participations]&.[](event.id)
    participation && EventParticipationResource.new(participation).serializable_hash
  end
end
