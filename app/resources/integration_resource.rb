# frozen_string_literal: true

# An Integration: whether the player linked the service, and which account.
class IntegrationResource < ApplicationResource
  attributes :provider

  attribute(:connected, &:connected?)
  attribute(:athlete_id) { |integration| integration.token&.athlete_id }
  attribute(:scope) { |integration| integration.token&.scope.presence }
  attribute(:connected_at) { |integration| integration.token&.created_at&.iso8601 }
end
