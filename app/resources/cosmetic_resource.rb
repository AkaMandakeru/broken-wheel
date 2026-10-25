# frozen_string_literal: true

# A cosmetic as the app draws it. Pictures (banners, frames) come as image URLs;
# everything — pictures included, for when their art is pending — carries
# `render`, the colours the web draws with Tailwind classes (see CosmeticStyle).
class CosmeticResource < ApplicationResource
  attributes :key, :kind, :rarity

  attribute(:name, &:display_name)
  attribute(:rarity_label, &:rarity_label)
  attribute(:image) { |cosmetic| cosmetic.artwork? ? ImageUrls.urls(cosmetic.image, :display) : nil }
  attribute(:render) { |cosmetic| CosmeticStyle.render_data(cosmetic) }
end
