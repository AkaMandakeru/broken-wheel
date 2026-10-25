# frozen_string_literal: true

# The signed-in player's own profile. Unlike UserSummaryResource this carries
# their email, personal fields and preferences, so it is only ever rendered for
# the player themselves.
class MeResource < ApplicationResource
  attributes :id, :email, :first_name, :last_name, :nickname, :coins,
             :document, :phone, :blood_type, :address

  attribute :display_name do |user|
    user.nickname.presence || [ user.first_name, user.last_name ].compact_blank.join(" ")
  end

  attribute :title do |user|
    user.title.presence && { key: user.title, label: user.title_label }
  end

  # The titles the player may pick from — the ones they have earned.
  attribute :available_titles do |user|
    user.available_titles.map { |key| { key: key.to_s, label: Titles.label(key) } }
  end

  attribute(:sports) { |user| Array(user.sports) }
  attribute(:locale) { |user| user.email_locale.to_s }
  attribute(:email_reminders, &:email_reminders?)
  attribute(:avatar) { |user| ImageUrls.urls(user.avatar, :thumb, :medium) }
  attribute(:connected_to_strava, &:connected_to_strava?)
  attribute(:created_at) { |user| user.created_at.iso8601 }

  # One entry per slot the profile draws, null when nothing is worn there.
  attribute :equipped do |user|
    Cosmetic::RENDERABLE_KINDS.index_with do |kind|
      cosmetic = user.equipped_cosmetic(kind)
      cosmetic && CosmeticResource.new(cosmetic).serializable_hash
    end
  end
end
