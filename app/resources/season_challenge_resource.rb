# frozen_string_literal: true

# A challenge on the season board, with the viewer's progress on it.
#
# Params: `progress` ({ challenge_id => ChallengeParticipation }, from
# Seasons::Dashboard#challenge_progress) and `participation` (the viewer's
# SeasonParticipation, for level locks). Both may be absent for a guest.
class SeasonChallengeResource < ApplicationResource
  attributes :id, :challenge_id, :category, :week_index, :position, :xp_reward, :coin_reward,
             :fragment_reward, :required, :unlock_level

  attribute(:title) { |sc| sc.challenge.display_title }
  attribute(:description) { |sc| sc.challenge.display_description }
  attribute(:category_label) { |sc| I18n.t("seasons.categories.#{sc.category}", default: sc.category.to_s.humanize) }
  attribute(:sport) { |sc| sc.challenge.sport }
  attribute(:image) { |sc| ImageUrls.urls(sc.challenge.image, :card, :hero) }
  attribute(:special) { |sc| sc.special? }
  attribute(:elite) { |sc| sc.elite? }
  attribute(:locked) { |sc| sc.locked_for?(params[:participation]) }

  # The dates it is scored over. `narrower_than_season` says whether they are
  # worth showing — a challenge spanning the whole season says nothing new.
  attribute(:starts_on) { |sc| sc.date_window&.begin&.iso8601 }
  attribute(:ends_on) { |sc| sc.date_window&.end&.iso8601 }
  attribute(:narrower_than_season) { |sc| sc.narrower_than_season? }
  attribute(:window_ended) { |sc| sc.window_ended? }

  attribute :requirements do |sc|
    statuses = statuses_for(sc)
    sc.challenge.challenge_requirements.each_with_index.map do |requirement, index|
      status = statuses&.at(index)
      {
        id: requirement.id,
        metric: requirement.metric,
        label: requirement.label,
        target: requirement.target.to_f,
        unit: requirement.display_unit,
        comparator: requirement.comparator,
        medal: weekly?(sc) ? Seasons::WeeklyMedals.for_requirement(index) : nil,
        progress: status && { value: status[:value]&.to_f, percent: status[:percent], met: status[:met] }
      }
    end
  end

  # Nil when the viewer isn't taking part in this challenge (or is a guest).
  attribute :progress do |sc|
    mine = mine_for(sc)
    next nil unless mine

    {
      completed: mine.completed?,
      completed_at: mine.completed_at&.iso8601,
      percent: mine.percent_complete,
      medal: weekly?(sc) ? Seasons::WeeklyMedals.highest_earned(mine, statuses: statuses_for(sc)) : nil
    }
  end

  private

  def mine_for(season_challenge)
    params[:progress]&.dig(season_challenge.challenge_id)
  end

  def weekly?(season_challenge)
    season_challenge.category == "weekly"
  end

  # requirement_status computes every requirement's value, so it is read once
  # per challenge and shared by both attributes.
  def statuses_for(season_challenge)
    @statuses ||= {}
    return @statuses[season_challenge.id] if @statuses.key?(season_challenge.id)

    @statuses[season_challenge.id] = mine_for(season_challenge)&.requirement_status
  end
end
