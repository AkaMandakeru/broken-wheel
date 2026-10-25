# frozen_string_literal: true

module Api
  # The API's side of FeatureGuarded: an admin switching a feature off closes
  # its endpoints too, answering 403 `feature_disabled` (with the feature's key)
  # instead of redirecting.
  #
  #   requires_feature :clubs
  #
  # Every response also carries X-Features-Version (see Api::FeatureSet), so an
  # app that has the menu cached learns about a switch on its next request.
  module FeatureGuard
    extend ActiveSupport::Concern

    included do
      # Before everything else, so it's on 401s and 403s too — a halted
      # callback chain skips after_actions.
      prepend_before_action :expose_features_version
    end

    class_methods do
      def requires_feature(key, **options)
        before_action(**options) { ensure_feature_enabled(key) }
      end
    end

    private

    def ensure_feature_enabled(key)
      return if Features.enabled?(key)

      render_error :forbidden, "feature_disabled", feature: key.to_s,
                   message: I18n.t("api.errors.feature_disabled", feature: Features.find(key)&.name || key)
    end

    def expose_features_version
      response.headers["X-Features-Version"] = Api::FeatureSet.version
    end
  end
end
