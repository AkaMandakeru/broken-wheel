# frozen_string_literal: true

module Api
  module V1
    module Auth
      # Log in, refresh, log out. Passwords are checked by Devise itself
      # (valid_for_authentication?), so the attempt counter, the lock after 20
      # failures and the unlock email behave exactly as on the web.
      class SessionsController < BaseController
        allow_unauthenticated_access only: [ :create, :refresh ]

        rate_limit to: 10, within: 3.minutes, only: :create, name: "login-ip",
                   with: -> { render_error :too_many_requests, "rate_limited" }
        rate_limit to: 10, within: 3.minutes, only: :create, name: "login-email",
                   by: -> { params[:email].to_s.downcase.strip },
                   with: -> { render_error :too_many_requests, "rate_limited" }
        rate_limit to: 30, within: 3.minutes, only: :refresh,
                   with: -> { render_error :too_many_requests, "rate_limited" }

        def create
          user = User.find_for_authentication(email: params[:email].to_s.downcase.strip)

          if user&.valid_for_authentication? { user.valid_password?(params[:password].to_s) } && user.active_for_authentication?
            tokens = ApiSession.start!(user, **device_attributes)
            track_event "api.session.created", user_id: user.id, platform: tokens.session.platform
            render_resource SessionResource, tokens, status: :created
          elsif user&.access_locked?
            render_error :unauthorized, "account_locked"
          else
            render_error :unauthorized, "invalid_credentials"
          end
        end

        def refresh
          tokens = ApiSession.refresh!(params[:refresh_token].to_s, app_version: app_version)
          return render_error(:unauthorized, "invalid_refresh_token") unless tokens

          render_resource SessionResource, tokens
        end

        def destroy
          current_session.revoke_family!(reason: "logout")
          track_event "api.session.destroyed"
          head :no_content
        end

        private

        def device_attributes
          { device_name: params[:device_name], platform: params[:platform], app_version: app_version }
        end
      end
    end
  end
end
