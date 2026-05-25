# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Strava OAuth", type: :request do
  let(:user) do
    User.create!(
      first_name: "Oauth",
      last_name: "Tester",
      email: "oauth-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  describe "POST /auth/strava (connect)" do
    it "redirects to sign in when unauthenticated" do
      post auth_strava_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects to Strava authorize URL when authenticated" do
      sign_in user
      post auth_strava_path

      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with("https://www.strava.com/oauth/authorize")
      expect(response.location).to include("client_id=")
      expect(response.location).to include("scope=read%2Cactivity%3Aread_all")
    end
  end

  describe "GET /auth/strava/callback" do
    it "redirects to sign in when unauthenticated" do
      get auth_strava_callback_path, params: { code: "abc" }
      expect(response).to redirect_to(new_user_session_path)
    end

    context "when user denies permission" do
      it "redirects to profile with error" do
        sign_in user
        get auth_strava_callback_path, params: { error: "access_denied" }

        expect(response).to redirect_to(profile_path)
        expect(flash[:alert]).to eq(I18n.t("flashes.strava.connect_failed"))
      end
    end

    context "when token exchange succeeds" do
      let(:token_response) do
        double(
          access_token: "strava-access",
          refresh_token: "strava-refresh",
          expires_at: Time.at(2.hours.from_now.to_i),
          athlete: double(id: 999)
        )
      end

      before do
        oauth_client = instance_double(Strava::OAuth::Client)
        allow(Strava::OAuth::Client).to receive(:new).and_return(oauth_client)
        allow(oauth_client).to receive(:oauth_token).with(code: "valid-code").and_return(token_response)
        allow(SyncStravaActivitiesJob).to receive(:perform_later)
      end

      it "creates a strava token and redirects to profile" do
        sign_in user
        get auth_strava_callback_path, params: { code: "valid-code", scope: "read,activity:read_all" }

        expect(response).to redirect_to(profile_path)
        expect(flash[:notice]).to eq(I18n.t("flashes.strava.connected"))

        token = user.reload.strava_token
        expect(token.access_token).to eq("strava-access")
        expect(token.refresh_token).to eq("strava-refresh")
        expect(token.athlete_id).to eq(999)
        expect(token.scope).to eq("read,activity:read_all")
      end

      it "enqueues a sync job" do
        sign_in user
        expect(SyncStravaActivitiesJob).to receive(:perform_later).with(user.id)

        get auth_strava_callback_path, params: { code: "valid-code" }
      end

      it "updates an existing token instead of creating a duplicate" do
        user.create_strava_token!(
          access_token: "old",
          refresh_token: "old-refresh",
          expires_at: 1.hour.ago.to_i
        )

        sign_in user
        get auth_strava_callback_path, params: { code: "valid-code" }

        expect(user.reload.strava_token.access_token).to eq("strava-access")
        expect(StravaToken.where(user: user).count).to eq(1)
      end
    end

    context "when token exchange fails" do
      it "redirects to profile with error" do
        oauth_client = instance_double(Strava::OAuth::Client)
        allow(Strava::OAuth::Client).to receive(:new).and_return(oauth_client)
        allow(oauth_client).to receive(:oauth_token).and_raise(
          Strava::Errors::Fault.new(nil, { status: 400, body: { "message" => "Bad Request" } })
        )

        sign_in user
        get auth_strava_callback_path, params: { code: "bad-code" }

        expect(response).to redirect_to(profile_path)
        expect(flash[:alert]).to eq(I18n.t("flashes.strava.connect_failed"))
      end
    end
  end

  describe "DELETE /auth/strava (disconnect)" do
    it "redirects to sign in when unauthenticated" do
      delete disconnect_strava_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "destroys the user's strava token" do
      user.create_strava_token!(
        access_token: "a",
        refresh_token: "r",
        expires_at: 1.hour.from_now.to_i
      )
      sign_in user

      delete disconnect_strava_path

      expect(response).to redirect_to(profile_path)
      expect(flash[:notice]).to eq(I18n.t("flashes.strava.disconnected"))
      expect(user.reload.strava_token).to be_nil
    end

    it "succeeds even if there is no token to destroy" do
      sign_in user
      delete disconnect_strava_path
      expect(response).to redirect_to(profile_path)
    end
  end
end
