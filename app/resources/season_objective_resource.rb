# frozen_string_literal: true

# A season objective (club goals and the like) or a legacy mission. Param
# `completed_ids` lists the ones the viewer has done.
class SeasonObjectiveResource < ApplicationResource
  attributes :id, :kind, :track, :icon, :target, :xp_reward, :coin_reward, :fragment_reward, :required

  attribute(:metric) { |objective| objective.metric_key }

  # Legacy missions are named by their value ("discipline"…), translated under
  # seasons.legacy, the way the season page shows them.
  attribute :title do |objective|
    if objective.legacy?
      I18n.t("seasons.legacy.#{objective.name}.title", default: objective.name.to_s.humanize)
    else
      objective.display_name
    end
  end

  attribute :description do |objective|
    if objective.legacy?
      I18n.t("seasons.legacy.#{objective.name}.description", count: objective.target, default: "")
    else
      objective.display_description
    end
  end

  attribute(:completed) { |objective| Array(params[:completed_ids]).include?(objective.id) }
end
