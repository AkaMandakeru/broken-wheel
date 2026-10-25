# frozen_string_literal: true

# One board of the season ranking (a Seasons::Dashboard): the top rows and the
# viewer's own place, so someone outside the top still sees where they stand.
# Values are raw numbers in `unit`; the app formats them.
class SeasonLeaderboardResource < ApplicationResource
  UNITS = { xp: "xp", distance: "km", activities: "count", streak: "days", fastest_5k: "seconds", elevation: "m" }.freeze

  attribute(:board) { |dashboard| dashboard.board.to_s }
  attribute(:board_label) { |dashboard| I18n.t("seasons.leaderboards.#{dashboard.board}") }
  attribute(:unit) { |dashboard| UNITS.fetch(dashboard.board) }

  attribute :boards do |_dashboard|
    SeasonLeaderboard.boards.map { |key| { key: key.to_s, label: I18n.t("seasons.leaderboards.#{key}") } }
  end

  attribute :rows do |dashboard|
    dashboard.leaderboard_rows.each_with_index.map do |row, index|
      {
        position: index + 1,
        value: dashboard.leaderboard.value_for(row)&.to_f,
        me: viewer.present? && row.user_id == viewer.id,
        user: UserSummaryResource.new(row.user).serializable_hash
      }
    end
  end

  attribute :me do |dashboard|
    participation = dashboard.participation
    next nil unless participation

    { position: dashboard.my_position, value: dashboard.leaderboard.value_for(participation)&.to_f }
  end
end
