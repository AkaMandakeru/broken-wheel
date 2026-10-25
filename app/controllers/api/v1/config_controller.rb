# frozen_string_literal: true

module Api
  module V1
    # What the app needs before anything else: which features are on, which
    # locales exist, and whether this build is still supported. Public, and
    # exempt from the version gate so an outdated build can learn it is one.
    class ConfigController < BaseController
      allow_unauthenticated_access
      skip_before_action :ensure_supported_app_version

      def show
        render_data({
          min_supported_version: Api::AppVersion.minimum,
          features: Features.all.to_h { |feature| [ feature.key, Features.enabled?(feature.key) ] },
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
