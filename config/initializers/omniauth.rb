Rails.application.config.middleware.use OmniAuth::Builder do
  provider :strava,
    Rails.application.credentials.strava[:client_id],
    Rails.application.credentials.strava[:client_secret],
    scope: "read,activity:read_all"
end