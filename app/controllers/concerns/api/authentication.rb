# frozen_string_literal: true

module Api
  # Bearer tokens only — no cookies, so there is no CSRF surface. The access
  # token is a signed ApiSession token (see ApiSession), checked with one
  # indexed lookup per request.
  #
  #   allow_unauthenticated_access only: :create   # sign-up, login…
  #   allow_unauthenticated_access only: :index, optional: true   # signed-in users get more
  module Authentication
    extend ActiveSupport::Concern

    included do
      before_action :authenticate!
    end

    class_methods do
      def allow_unauthenticated_access(**options)
        skip_before_action :authenticate!, **options
      end
    end

    private

    def current_session = resume_session

    def current_user = resume_session&.user

    def user_signed_in? = current_user.present?

    def authenticate!
      return if resume_session

      render_error :unauthorized, "unauthorized"
    end

    def resume_session
      return @current_session if defined?(@current_session)

      @current_session = ApiSession.authenticate_access(bearer_token)
    end

    def bearer_token
      request.authorization.to_s[/\ABearer (.+)\z/, 1]
    end
  end
end
