# frozen_string_literal: true

module Api
  module V1
    # Every mobile endpoint inherits from here. ActionController::API leaves out
    # cookies, sessions, CSRF, views and ApplicationController's allow_browser —
    # which would turn native clients away as "unsupported browsers".
    #
    # The order of the concerns is the order their callbacks run: the locale is
    # set first so even an authentication error comes back translated.
    class BaseController < ActionController::API
      include ActiveStorage::SetCurrent
      include Pagy::Method
      include Api::ErrorHandling
      include Api::Localized
      include Api::Authentication
      include Api::VersionGate
      include Api::FeatureGuard
      include Api::Idempotent
      include Api::Paginated
      include Api::Rendering
      include Api::Events
    end
  end
end
