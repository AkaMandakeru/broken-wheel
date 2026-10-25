# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 season dailies", type: :request do
  before { travel_to Time.utc(2026, 8, 15, 12) }
  after { travel_back }

  let(:user) { build_user }
  let!(:season) { Seasons::BlueprintImporter.call("season_8_legacy_of_champions") }

  path "/api/v1/seasons/{season_id}/dailies" do
    parameter name: :season_id, in: :path, schema: { type: :integer }

    get "Today's dailies, drawn on the spot when not yet assigned, with live progress" do
      tags "Seasons"
      produces "application/json"

      response "200", "today's dailies" do
        schema SeasonsSchemas.data(
          type: :object, required: %w[date completed_count total dailies],
          properties: {
            date: { type: :string, format: :date },
            completed_count: { type: :integer },
            total: { type: :integer },
            dailies: { type: :array, items: SeasonsSchemas::DAILY }
          }
        )
        let(:season_id) { season.id }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        run_test! do
          expect(json_data["date"]).to eq("2026-08-15")
          expect(json_data["total"]).to eq(3)
          expect(DailyChallengeAssignment.where(user: user, season: season).count).to eq(3)
        end
      end

      response "401", "signed out" do
        schema "$ref" => "#/components/schemas/error"
        let(:season_id) { season.id }
        let(:Authorization) { nil }

        run_test!
      end
    end
  end

  it "draws the same three the season page would, and keeps them" do
    get "/api/v1/seasons/#{season.id}/dailies", headers: api_headers(user)
    first = json_data["dailies"].pluck("id")

    get "/api/v1/seasons/#{season.id}/dailies", headers: api_headers(user)
    expect(json_data["dailies"].pluck("id")).to eq(first)
  end

  it "shows today's workouts before the next recalculation" do
    build_workout(user, date: Date.new(2026, 8, 15), km: 5)

    get "/api/v1/seasons/#{season.id}/dailies", headers: api_headers(user)

    distance = json_data["dailies"].find { |daily| daily["metric"] == "distance_km" }
    expect(distance["value"]).to eq(5.0) if distance
    expect(json_data["dailies"].pluck("value")).to all(be_a(Numeric).or(be_nil))
  end

  it "has nothing to offer on a season that isn't running" do
    season.update_columns(status: "upcoming")

    get "/api/v1/seasons/#{season.id}/dailies", headers: api_headers(user)

    expect(json_data["dailies"]).to eq([])
  end
end
