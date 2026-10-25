# frozen_string_literal: true

# Helpers for the mobile API's request specs (spec/requests/api).
module ApiHelpers
  # A signed-in device for `user`: ApiSession::Tokens.
  def api_sign_in(user, **device)
    ApiSession.start!(user, **device)
  end

  # Headers for a request as `user` (or anonymous with nil).
  def api_headers(user = nil, **extra)
    headers = { "Accept" => "application/json" }
    headers["Authorization"] = "Bearer #{api_sign_in(user).access_token}" if user
    headers.merge(extra.transform_keys(&:to_s))
  end

  def json_body
    JSON.parse(response.body)
  end

  def json_data
    json_body.fetch("data")
  end

  def json_error_code
    json_body.dig("error", "code")
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
