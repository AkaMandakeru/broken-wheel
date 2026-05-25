# frozen_string_literal: true

# OmniAuth is kept for future providers (Google, etc.).
# Strava uses strava-ruby-client directly via OauthController.

Rails.application.config.middleware.use OmniAuth::Builder do
  # provider :google_oauth2, ...
end
