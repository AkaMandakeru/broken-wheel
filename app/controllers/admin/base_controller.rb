# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    layout "admin"

    private

    def require_admin!
      return if current_user&.admin?

      redirect_to root_path, alert: t("admin.flashes.not_authorized")
    end
  end
end
