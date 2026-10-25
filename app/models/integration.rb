# frozen_string_literal: true

# A linked outside service, as the app's integrations screen shows it.
Integration = Data.define(:provider, :token) do
  def self.strava(user)
    new(provider: "strava", token: user.connected_to_strava? ? user.strava_token : nil)
  end

  def connected? = token.present?
end
