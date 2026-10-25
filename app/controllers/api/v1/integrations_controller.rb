# frozen_string_literal: true

module Api
  module V1
    # Which outside services the player has linked. Strava is the only one so
    # far; it's a list so the app needn't change when another arrives.
    class IntegrationsController < BaseController
      requires_feature :integrations

      def index
        render_collection IntegrationResource, [ Integration.strava(current_user) ]
      end
    end
  end
end
