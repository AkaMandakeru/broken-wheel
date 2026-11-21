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

      # Link name => [env var that overrides it, page on the company site].
      LEGAL_LINKS = {
        privacy_policy: [ "PRIVACY_POLICY_URL", "https://mandakeru-labs.com/broken-wheels/privacy" ],
        terms: [ "TERMS_URL", "https://mandakeru-labs.com/broken-wheels/terms" ],
        delete_account: [ "DELETE_ACCOUNT_URL", "https://mandakeru-labs.com/broken-wheels/delete-account" ]
      }.freeze

      def show
        legal = legal_links
        # The legal links are in the ETag so a change to them reaches apps
        # holding a cached copy, not just a feature switch.
        return unless stale?(etag: [ Api::FeatureSet.version, Api::AppVersion.minimum, I18n.locale, legal ])

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
            **legal
          }
        })
      end

      private

      def legal_links
        LEGAL_LINKS.transform_values { |(env_var, default)| ENV[env_var].presence || default }
      end
    end
  end
end
