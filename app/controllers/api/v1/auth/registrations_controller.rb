# frozen_string_literal: true

module Api
  module V1
    module Auth
      # Sign-up from the app, signed in straight away — the same as the web.
      class RegistrationsController < BaseController
        allow_unauthenticated_access only: :create

        rate_limit to: 5, within: 10.minutes, only: :create

        def create
          user = Accounts::Registration.call(registration_params, source: signup_source)
          return render_invalid(user) unless user.persisted?

          tokens = ApiSession.start!(user, device_name: params[:device_name], platform: params[:platform],
                                           app_version: app_version)
          user.remember_locale(I18n.locale)
          track_event "api.user.registered", user_id: user.id
          render_resource SessionResource, tokens, status: :created
        end

        private

        # Neither app sends a platform on sign-up yet, so this is often just
        # "App"; the param or X-Platform header adds it when present.
        def signup_source
          Accounts::Registration.app_source(platform: params[:platform].presence || request.headers["X-Platform"],
                                            app_version: app_version)
        end

        def registration_params
          attributes = params.expect(user: [ :first_name, :last_name, :nickname, :email, :password ])
          attributes.merge(password_confirmation: attributes[:password])
        end
      end
    end
  end
end
