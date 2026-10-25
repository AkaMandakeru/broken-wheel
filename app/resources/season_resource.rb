# frozen_string_literal: true

# A season as it appears in the list and in the page header.
class SeasonResource < ApplicationResource
  attributes :id, :key, :name, :slogan, :description, :theme, :status, :time_zone, :max_level

  attribute(:status_label) { |season| I18n.t("seasons.statuses.#{season.status}", default: season.status.to_s.humanize) }
  attribute(:starts_at) { |season| season.starts_at&.iso8601 }
  attribute(:ends_at) { |season| season.ends_at&.iso8601 }

  # "Today" in the season's own timezone — what dailies and one-day events go by.
  attribute(:current_date) { |season| season.current_date.iso8601 }
  attribute(:battle_pass) { |season| season.battle_pass? }
  attribute(:image) { |season| ImageUrls.urls(season.image, :card, :hero) }
end
