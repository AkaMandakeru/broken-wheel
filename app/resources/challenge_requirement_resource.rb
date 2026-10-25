# frozen_string_literal: true

class ChallengeRequirementResource < ApplicationResource
  attributes :id, :metric, :comparator, :label

  attribute(:target) { |requirement| requirement.target.to_f }
  attribute(:unit, &:display_unit)
end
