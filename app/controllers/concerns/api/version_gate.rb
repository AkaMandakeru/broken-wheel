# frozen_string_literal: true

module Api
  # Builds older than MOBILE_MIN_SUPPORTED_VERSION get 426 and an
  # "update the app" screen. Requests without X-App-Version (scripts, tests,
  # the web) are let through; GET /config always is, so an old build can still
  # learn that it is old.
  module VersionGate
    extend ActiveSupport::Concern

    included do
      before_action :ensure_supported_app_version
    end

    private

    def ensure_supported_app_version
      return unless app_version && Api::AppVersion.unsupported?(app_version)

      render_error :upgrade_required, "upgrade_required"
    end

    def app_version
      request.headers["X-App-Version"].presence
    end
  end
end
