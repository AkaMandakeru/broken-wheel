# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 config", type: :request do
  feature_schema = {
    type: :object,
    required: %w[key name description icon],
    properties: {
      key: { type: :string, enum: Features.keys },
      name: { type: :string },
      description: { type: :string },
      icon: {
        type: :object,
        required: %w[set style name],
        properties: {
          set: { type: :string, enum: [ FeatureResource::ICON_SET ] },
          style: { type: :string, example: "solid" },
          name: { type: :string, example: "trophy" }
        }
      }
    }
  }

  path "/api/v1/config" do
    get "App configuration: available features, locales, minimum version" do
      tags "Config"
      description <<~TEXT
        Show only the features listed in `features`, in that order; anything else is
        switched off. Every API response carries an `X-Features-Version` header: when it
        differs from `features_version`, fetch this again (it supports `If-None-Match`).
      TEXT
      security []
      produces "application/json"
      parameter "$ref" => "#/components/parameters/accept_language"

      response "200", "configuration" do
        header "X-Features-Version", schema: { type: :string }, description: "Changes whenever a feature is switched on or off"
        schema type: :object, required: [ "data" ], properties: {
          data: {
            type: :object,
            required: %w[features unavailable_features features_version locales default_locale links],
            properties: {
              min_supported_version: { type: :string, nullable: true },
              features: { type: :array, items: feature_schema },
              unavailable_features: {
                type: :array,
                items: { type: :object, required: %w[key name], properties: { key: { type: :string, enum: Features.keys }, name: { type: :string } } }
              },
              features_version: { type: :string },
              locales: { type: :array, items: { type: :string } },
              default_locale: { type: :string },
              links: { type: :object, additionalProperties: { type: :string, nullable: true } }
            }
          }
        }

        before { FeatureFlag.create!(key: "clubs", enabled: false) }

        run_test! do
          expect(json_data["features"].pluck("key")).to eq(Features.keys - [ "clubs" ])
          expect(json_data["unavailable_features"]).to eq([ { "key" => "clubs", "name" => Features.find("clubs").name } ])
          expect(json_data["features"].first["icon"]).to eq("set" => "FontAwesome6", "style" => "solid", "name" => "trophy")
          expect(response.headers["X-Features-Version"]).to eq(json_data["features_version"])
          expect(json_data["locales"]).to eq(%w[en pt])
        end
      end
    end
  end

  it "names the features in the app's language" do
    get "/api/v1/config", headers: { "Accept-Language" => "pt-BR" }

    seasons = json_data["features"].find { |feature| feature["key"] == "seasons" }
    expect(seasons["name"]).to eq(I18n.t("features.seasons.name", locale: :pt))
  end

  it "answers 304 until a feature is switched, then the new menu" do
    get "/api/v1/config"
    etag = response.headers["ETag"]

    get "/api/v1/config", headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:not_modified)

    FeatureFlag.create!(key: "events", enabled: false)
    Features.reset_cache

    get "/api/v1/config", headers: { "If-None-Match" => etag }
    expect(response).to have_http_status(:ok)
    expect(json_data["features"].pluck("key")).not_to include("events")
  end

  describe "X-Features-Version on every response" do
    let(:user) { build_user }

    it "changes when a feature is switched, even on errors" do
      get "/api/v1/me", headers: api_headers(user)
      before = response.headers["X-Features-Version"]
      expect(before).to be_present

      FeatureFlag.create!(key: "workouts", enabled: false)
      Features.reset_cache

      get "/api/v1/workouts", headers: api_headers(user)
      expect(response).to have_http_status(:forbidden)
      expect(response.headers["X-Features-Version"]).not_to eq(before)

      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["X-Features-Version"]).to be_present
    end

    it "names the switched-off feature in the 403, so the app can hide it" do
      FeatureFlag.create!(key: "clubs", enabled: false)

      get "/api/v1/clubs", headers: api_headers(user)

      expect(response).to have_http_status(:forbidden)
      expect(json_body["error"]).to include("code" => "feature_disabled", "feature" => "clubs")
    end
  end
end
