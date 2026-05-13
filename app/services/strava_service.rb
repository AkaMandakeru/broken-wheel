class StravaService
  BASE_URL = "https://www.strava.com/api/v3"

  def initialize(user)
    @user  = user
    @token = user.strava_token
    refresh_token! if @token.expired?
  end

  def athlete
    get("/athlete")
  end

  def activities(per_page: 30, page: 1)
    get("/athlete/activities", per_page: per_page, page: page)
  end

  private

  def get(path, params = {})
    HTTParty.get("#{BASE_URL}#{path}", headers: auth_headers, query: params)
  end

  def auth_headers
    { "Authorization" => "Bearer #{@token.access_token}" }
  end

  def refresh_token!
    response = HTTParty.post("https://www.strava.com/oauth/token", body: {
      client_id:     Rails.application.credentials.strava[:client_id],
      client_secret: Rails.application.credentials.strava[:client_secret],
      grant_type:    "refresh_token",
      refresh_token: @token.refresh_token
    })

    @token.update!(
      access_token: response["access_token"],
      refresh_token: response["refresh_token"],
      expires_at:   response["expires_at"]
    )
  end
end