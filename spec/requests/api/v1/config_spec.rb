# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 config", type: :request do
  path "/api/v1/config" do
    get "App configuration: features, locales, minimum version" do
      tags "Config"
      security []
      produces "application/json"

      response "200", "configuration" do
        schema type: :object, required: [ "data" ], properties: {
          data: {
            type: :object,
            required: %w[features locales default_locale links],
            properties: {
              min_supported_version: { type: :string, nullable: true },
              features: { type: :object, additionalProperties: { type: :boolean } },
              locales: { type: :array, items: { type: :string } },
              default_locale: { type: :string },
              links: { type: :object, additionalProperties: { type: :string, nullable: true } }
            }
          }
        }

        before { FeatureFlag.create!(key: "clubs", enabled: false) }

        run_test! do
          expect(json_data["features"]).to include("clubs" => false, "seasons" => true)
          expect(json_data["locales"]).to eq(%w[en pt])
        end
      end
    end
  end
end
