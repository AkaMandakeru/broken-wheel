# frozen_string_literal: true

# A switchable feature (Features::CATALOGUE) as the app's menu needs it: what to
# call it and which icon to draw. The web's Font Awesome class is turned into
# a name the app's icon set understands ("fa-solid fa-trophy" → "trophy").
class FeatureResource < ApplicationResource
  ICON_SET = "FontAwesome6"

  attributes :key, :name, :description

  attribute :icon do |feature|
    style, name = feature.icon.to_s.split.map { |part| part.delete_prefix("fa-") }
    { set: ICON_SET, style: style, name: name }
  end
end
