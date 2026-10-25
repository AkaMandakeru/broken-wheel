# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 integrations", type: :request do
  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

  path "/api/v1/integrations" do
    get "Linked outside services" do
      tags "Integrations"
      produces "application/json"

      response "200", "the player's integrations" do
        schema type: :object, required: [ "data" ], properties: {
          data: { type: :array, items: WorkoutsSchemas::INTEGRATION }
        }

        before do
          user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i,
                                    athlete_id: 999, scope: "read,activity:read_all")
        end

        run_test! do
          expect(json_data.sole).to include("provider" => "strava", "connected" => true, "athlete_id" => 999,
                                            "scope" => "read,activity:read_all",
                                            "connected_at" => user.strava_token.created_at.iso8601)
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }

        run_test!
      end

      response "403", "integrations are switched off" do
        schema "$ref" => "#/components/schemas/error"
        before { FeatureFlag.create!(key: "integrations", enabled: false) }

        run_test! { expect(json_error_code).to eq("feature_disabled") }
      end
    end
  end

  it "shows Strava as not connected before the player links it" do
    get "/api/v1/integrations", headers: api_headers(user)

    expect(json_data).to eq([ { "provider" => "strava", "connected" => false, "athlete_id" => nil,
                                "scope" => nil, "connected_at" => nil } ])
  end
end
