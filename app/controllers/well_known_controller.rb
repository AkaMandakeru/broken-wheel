# frozen_string_literal: true

# The files iOS and Android fetch to let the native apps open this site's links
# (universal links / app links) and share its saved passwords. Each one is
# configured from the environment and is a 404 until it is.
class WellKnownController < ActionController::API
  # The web pages people share; the app has a screen for each. The Strava
  # redirect is added from STRAVA_MOBILE_REDIRECT_URI.
  APP_PATHS = %w[/seasons/* /challenges/* /events/* /clubs/*].freeze

  before_action { expires_in 1.hour, public: true }

  # https://developer.apple.com/documentation/xcode/supporting-associated-domains
  # Served as JSON at a path without an extension, with no redirect.
  def apple_app_site_association
    app_ids = env_list("IOS_APP_IDS")
    return head :not_found if app_ids.empty?

    render json: {
      applinks: { details: [ { appIDs: app_ids, components: app_paths.map { |path| { "/" => path } } } ] },
      webcredentials: { apps: app_ids }
    }
  end

  # https://developer.android.com/training/app-links/verify-android-applinks
  def assetlinks
    package = ENV["ANDROID_APP_PACKAGE"].presence
    fingerprints = env_list("ANDROID_SHA256_CERT_FINGERPRINTS")
    return head :not_found if package.nil? || fingerprints.empty?

    render json: [ {
      relation: [ "delegate_permission/common.handle_all_urls", "delegate_permission/common.get_login_creds" ],
      target: { namespace: "android_app", package_name: package, sha256_cert_fingerprints: fingerprints }
    } ]
  end

  private

  def app_paths
    strava_path = URI.parse(ENV["STRAVA_MOBILE_REDIRECT_URI"].to_s).path.presence
    strava_path ? APP_PATHS + [ "#{strava_path}*" ] : APP_PATHS
  rescue URI::InvalidURIError
    APP_PATHS
  end

  def env_list(name)
    ENV[name].to_s.split(",").map(&:strip).compact_blank
  end
end
