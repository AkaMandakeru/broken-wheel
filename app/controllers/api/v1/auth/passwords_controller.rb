# frozen_string_literal: true

module Api
  module V1
    module Auth
      # "Forgot password" from the app. Devise sends its usual email, and the
      # link opens the web reset page — Devise keeps owning the reset token.
      #
      # Always 202, whether or not the email has an account, so the endpoint
      # cannot be used to find out who is registered.
      class PasswordsController < BaseController
        allow_unauthenticated_access only: :create

        rate_limit to: 5, within: 10.minutes, only: :create,
                   with: -> { render_error :too_many_requests, "rate_limited" }

        def create
          User.send_reset_password_instructions(email: params[:email].to_s.downcase.strip)
          head :accepted
        end
      end
    end
  end
end
