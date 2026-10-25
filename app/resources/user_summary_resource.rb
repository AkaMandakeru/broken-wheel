# frozen_string_literal: true

# How another player appears in lists, boards and feeds: never their email or
# personal fields.
class UserSummaryResource < ApplicationResource
  attributes :id, :first_name, :last_name, :nickname

  attribute :display_name do |user|
    user.nickname.presence || [ user.first_name, user.last_name ].compact_blank.join(" ")
  end

  attribute :title do |user|
    user.title.presence && { key: user.title, label: user.title_label }
  end

  attribute :avatar do |user|
    ImageUrls.urls(user.avatar, :thumb, :medium)
  end
end
