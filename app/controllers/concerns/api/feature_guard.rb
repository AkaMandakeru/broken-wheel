# frozen_string_literal: true

module Api
  # The API's side of FeatureGuarded: an admin switching a feature off closes
  # its endpoints too, answering 403 `feature_disabled` instead of redirecting.
  #
  #   requires_feature :clubs
  module FeatureGuard
    extend ActiveSupport::Concern

    class_methods do
      def requires_feature(key, **options)
        before_action(**options) { ensure_feature_enabled(key) }
      end
    end

    private

    def ensure_feature_enabled(key)
      return if Features.enabled?(key)

      render_error :forbidden, "feature_disabled",
                   message: I18n.t("api.errors.feature_disabled", feature: Features.find(key)&.name || key)
    end
  end
end
