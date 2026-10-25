# frozen_string_literal: true

module Api
  module V1
    # What the app needs before anything else: which features are on, which
    # locales exist, and whether this build is still supported. Public, and
    # exempt from the version gate so an outdated build can learn it is one.
    # ETagged, so refetching it after X-Features-Version changes is cheap.
    class ConfigController < BaseController
      allow_unauthenticated_access
      skip_before_action :ensure_supported_app_version

      def show
        return unless stale?(etag: [ Api::FeatureSet.version, Api::AppVersion.minimum, I18n.locale ])

        render_data({
          min_supported_version: Api::AppVersion.minimum,
          # Only what the app should show, in menu order. Anything not listed is
          # off: hide its tab and entry points.
          features: FeatureResource.new(Api::FeatureSet.available).serializable_hash,
          # Switched off by an admin — named, so a deep link into one can say
          # "Clubs is unavailable right now" instead of failing.
          unavailable_features: Api::FeatureSet.unavailable.map { |feature| { key: feature.key, name: feature.name } },
          features_version: Api::FeatureSet.version,
          locales: I18n.available_locales.map(&:to_s),
          default_locale: I18n.default_locale.to_s,
          links: {
            web: root_url,
            password_reset: new_user_password_url,
            privacy_policy: ENV["PRIVACY_POLICY_URL"].presence,
            terms: ENV["TERMS_URL"].presence
          }
        })
      end
    end
  end
end
