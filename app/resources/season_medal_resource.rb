# frozen_string_literal: true

# One season on the medal shelf: a SeasonParticipation, with what it took and
# what the next tier still costs.
class SeasonMedalResource < ApplicationResource
  attributes :level, :completion_percent, :medal_fragments, :medal_tier, :next_medal_tier,
             :fragments_to_next_medal, :medal_progress_percent

  attribute :season do |participation|
    season = participation.season
    {
      id: season.id, key: season.key, name: season.name, ends_at: season.ends_at&.iso8601,
      image: ImageUrls.urls(season.image, :card, :hero),
      # Whether GET /seasons/:id will open it.
      browsable: params[:browsable] == true
    }
  end

  attribute :medal_label do |participation|
    tier = participation.medal_tier
    tier && I18n.t("seasons.medals.#{tier}")
  end
end
