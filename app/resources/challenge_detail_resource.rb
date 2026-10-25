# frozen_string_literal: true

# One challenge's page, read in a Challenges::Context (`params[:context]`):
# the viewer's progress and the ranking come from the same season.
class ChallengeDetailResource < ChallengeResource
  RANKING_SIZE = 100

  attribute :season do |_challenge|
    season = params[:context].season
    season && { id: season.id, name: season.name }
  end

  attribute :my_participation do |_challenge|
    participation = params[:context].participation
    participation && ChallengeParticipationResource.new(participation).serializable_hash
  end

  attribute :ranking do |_challenge|
    params[:context].ranking.limit(RANKING_SIZE).each_with_index.map do |participation, index|
      {
        rank: index + 1,
        user: UserSummaryResource.new(participation.user).serializable_hash,
        progress_value: participation.progress_value.to_f,
        percent_complete: participation.percent_complete,
        completed: participation.completed?,
        me: participation.user_id == viewer&.id
      }
    end
  end
end
