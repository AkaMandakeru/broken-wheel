# frozen_string_literal: true

# Closes a feature's URLs when an admin switches it off.
#
# Hiding the nav link is not disabling a feature — anyone with the URL, a
# bookmark or a stale tab would walk straight in. The catalogue maps controllers
# to features, so every route under a disabled feature turns away here.
#
# Admin controllers are deliberately absent from that map: an admin must always
# be able to reach the screen that switches things back on.
module FeatureGuarded
  extend ActiveSupport::Concern

  included do
    before_action :ensure_feature_enabled
    helper_method :feature_enabled?
  end

  private

  def feature_enabled?(key)
    Features.enabled?(key)
  end

  def ensure_feature_enabled
    feature = Features.for_controller(controller_path)
    return if feature.nil? || Features.enabled?(feature.key)

    respond_to do |format|
      format.html { redirect_to feature_fallback_path, alert: t("features.unavailable", feature: feature.name) }
      format.any  { head :not_found }
    end
  end

  # Somewhere that is definitely still switched on, so turning a feature off
  # can never bounce a user between two blocked pages.
  def feature_fallback_path
    return root_path unless user_signed_in?

    logged_in_home_path
  end
end
