# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 devices", type: :request do
  let(:user) { build_user }
  let(:expo_token) { "ExponentPushToken[xxxxxxxxxxxxxxxxxxxxxx]" }

  device_schema = {
    type: :object,
    required: %w[id platform token last_seen_at created_at],
    properties: {
      id: { type: :integer },
      platform: { type: :string, enum: DeviceToken::PLATFORMS },
      token: { type: :string },
      app_version: { type: :string, nullable: true },
      locale: { type: :string, nullable: true },
      last_seen_at: { type: :string, format: "date-time", nullable: true },
      created_at: { type: :string, format: "date-time" }
    }
  }

  path "/api/v1/devices" do
    post "Register this device for push notifications" do
      tags "Devices"
      description "Call on every launch with the Expo push token. A token already registered (even to another account) " \
                  "moves to the signed-in user."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: [ "device" ],
        properties: {
          device: {
            type: :object,
            required: %w[platform token],
            properties: {
              platform: { type: :string, enum: DeviceToken::PLATFORMS },
              token: { type: :string, example: "ExponentPushToken[xxxxxxxxxxxxxxxxxxxxxx]" },
              app_version: { type: :string, example: "1.0.0" },
              locale: { type: :string, example: "pt-BR" }
            }
          }
        }
      }

      response "201", "registered" do
        schema type: :object, required: [ "data" ], properties: { data: device_schema }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let(:body) { { device: { platform: "expo", token: expo_token, app_version: "1.0.0", locale: "pt-BR" } } }

        run_test! do
          expect(json_data).to include("token" => expo_token, "app_version" => "1.0.0", "locale" => "pt-BR")
          expect(user.device_tokens.sole.last_seen_at).to be_within(5.seconds).of(Time.current)
        end
      end

      response "200", "already registered — moved to this account" do
        schema type: :object, required: [ "data" ], properties: { data: device_schema }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let(:body) { { device: { platform: "expo", token: expo_token, app_version: "1.1.0" } } }
        let!(:existing) { DeviceToken.create!(user: build_user, platform: "expo", token: expo_token, last_seen_at: 3.days.ago) }

        run_test! do
          expect(existing.reload).to have_attributes(user: user, app_version: "1.1.0")
          expect(existing.last_seen_at).to be_within(5.seconds).of(Time.current)
          expect(DeviceToken.count).to eq(1)
        end
      end

      response "422", "not an Expo push token" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let(:body) { { device: { platform: "expo", token: "not-a-token" } } }

        run_test! do
          expect(json_error_code).to eq("validation_failed")
          expect(json_body.dig("error", "fields", "token")).to be_present
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }
        let(:body) { { device: { platform: "expo", token: expo_token } } }

        run_test!
      end
    end
  end

  path "/api/v1/devices/{token}" do
    delete "Stop sending pushes to this device (on sign-out)" do
      tags "Devices"
      produces "application/json"
      parameter name: :token, in: :path, schema: { type: :string }, description: "The Expo push token, URL-encoded"

      response "204", "removed" do
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let!(:device) { DeviceToken.create!(user: user, platform: "expo", token: expo_token) }
        let(:token) { CGI.escape(expo_token) }

        run_test! do
          expect(DeviceToken.exists?(device.id)).to be(false)
        end
      end

      response "404", "not one of your devices" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let!(:device) { DeviceToken.create!(user: build_user, platform: "expo", token: expo_token) }
        let(:token) { CGI.escape(expo_token) }

        run_test! do
          expect(DeviceToken.exists?(device.id)).to be(true)
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }
        let(:token) { CGI.escape(expo_token) }

        run_test!
      end
    end
  end

  it "accepts the newer ExpoPushToken prefix" do
    post "/api/v1/devices", headers: api_headers(user), as: :json,
                            params: { device: { platform: "expo", token: "ExpoPushToken[abc123]" } }

    expect(response).to have_http_status(:created)
  end

  it "rejects an unknown platform" do
    post "/api/v1/devices", headers: api_headers(user), as: :json,
                            params: { device: { platform: "fcm", token: expo_token } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body.dig("error", "fields")).to have_key("platform")
  end

  it "has the token message in Portuguese too" do
    device = DeviceToken.new(user: user, platform: "expo", token: "nope")

    device.validate

    expect(I18n.with_locale(:pt) { device.errors[:token] }).to include("não é um token de push da Expo")
  end
end
