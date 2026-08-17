# frozen_string_literal: true

module Admin
  # Switches user-facing features on and off. Turning one off hides its nav
  # entries and closes its URLs; see Features and FeatureGuarded.
  class FeaturesController < BaseController
    def index
      @features = Features.all
    end

    def update
      feature = Features.find(params[:id])
      return redirect_to admin_features_path, alert: t("admin.features.unknown") if feature.nil?

      enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      FeatureFlag.set(feature.key, enabled, actor: current_user.email)

      redirect_to admin_features_path,
                  notice: t(enabled ? "admin.features.enabled" : "admin.features.disabled", feature: feature.name)
    end
  end
end
