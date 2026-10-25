# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Universal links / app links", type: :request do
  around do |example|
    keys = %w[IOS_APP_IDS ANDROID_APP_PACKAGE ANDROID_SHA256_CERT_FINGERPRINTS STRAVA_MOBILE_REDIRECT_URI]
    saved = ENV.to_h.slice(*keys)
    keys.each { ENV.delete(it) }
    example.run
  ensure
    keys.each { ENV.delete(it) }
    ENV.update(saved)
  end

  describe "GET /.well-known/apple-app-site-association" do
    it "is a 404 until the iOS app ids are set" do
      get "/.well-known/apple-app-site-association"

      expect(response).to have_http_status(:not_found)
    end

    it "lists the app ids and the shareable paths as JSON, without a redirect" do
      ENV["IOS_APP_IDS"] = "ABCDE12345.com.example.app, ABCDE12345.com.example.app.beta"
      ENV["STRAVA_MOBILE_REDIRECT_URI"] = "https://example.com/strava/mobile/callback"

      get "/.well-known/apple-app-site-association"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      body = JSON.parse(response.body)
      app_ids = %w[ABCDE12345.com.example.app ABCDE12345.com.example.app.beta]
      details = body.dig("applinks", "details").sole
      expect(details["appIDs"]).to eq(app_ids)
      expect(details["components"]).to include({ "/" => "/seasons/*" }, { "/" => "/challenges/*" },
                                               { "/" => "/events/*" }, { "/" => "/clubs/*" },
                                               { "/" => "/strava/mobile/callback*" })
      expect(body.dig("webcredentials", "apps")).to eq(app_ids)
    end

    it "leaves the Strava path out when there is no mobile redirect" do
      ENV["IOS_APP_IDS"] = "ABCDE12345.com.example.app"

      get "/.well-known/apple-app-site-association"

      paths = JSON.parse(response.body).dig("applinks", "details", 0, "components").map { it["/"] }
      expect(paths).to eq(WellKnownController::APP_PATHS)
    end
  end

  describe "GET /.well-known/assetlinks.json" do
    it "is a 404 until the Android package and fingerprints are set" do
      ENV["ANDROID_APP_PACKAGE"] = "com.example.app"

      get "/.well-known/assetlinks.json"

      expect(response).to have_http_status(:not_found)
    end

    it "lists the package and its signing certificates" do
      ENV["ANDROID_APP_PACKAGE"] = "com.example.app"
      ENV["ANDROID_SHA256_CERT_FINGERPRINTS"] = "AA:BB,CC:DD"

      get "/.well-known/assetlinks.json"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      statement = JSON.parse(response.body).sole
      expect(statement["relation"]).to include("delegate_permission/common.handle_all_urls")
      expect(statement["target"]).to eq(
        "namespace" => "android_app", "package_name" => "com.example.app", "sha256_cert_fingerprints" => [ "AA:BB", "CC:DD" ]
      )
    end
  end
end
