# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 season rewards", type: :request do
  before { travel_to Time.utc(2026, 8, 15, 12) }
  after { travel_back }

  let(:user) { build_user }
  let!(:season) { Seasons::BlueprintImporter.call("season_8_legacy_of_champions") }

  path "/api/v1/seasons/{season_id}/rewards" do
    parameter name: :season_id, in: :path, schema: { type: :integer }

    get "The battle pass (free and premium slot per level) and the bonus rewards" do
      tags "Seasons"
      security [ {}, { bearer: [] } ]
      produces "application/json"

      response "200", "rewards" do
        reward = { allOf: [ SeasonsSchemas::REWARD ], nullable: true }
        schema SeasonsSchemas.data(
          type: :object, required: %w[premium current_level levels bonus],
          properties: {
            premium: { type: :boolean },
            current_level: { type: :integer, nullable: true },
            levels: {
              type: :array,
              items: {
                type: :object, required: %w[level reached free premium],
                properties: { level: { type: :integer }, reached: { type: :boolean }, free: reward, premium: reward }
              }
            },
            bonus: { type: :array, items: SeasonsSchemas::REWARD }
          }
        )
        let(:season_id) { season.id }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let!(:granted) do
          participation = SeasonProgressService.ensure_participation(user, season)
          reward = season.season_rewards.find_by!(unlock_kind: "level", level: 1, track: "free")
          participation.season_reward_grants.create!(season_reward: reward, granted_at: Time.current)
          reward
        end

        run_test! do
          expect(json_data["levels"].size).to eq(season.max_level)
          level_one = json_data["levels"].first
          expect(level_one).to include("level" => 1, "reached" => true)
          expect(level_one.dig("free", "id")).to eq(granted.id)
          expect(level_one.dig("free", "granted")).to be(true)
          expect(json_data["levels"].second["reached"]).to be(false)
          expect(json_data["bonus"]).not_to be_empty
          expect(json_data["bonus"].pluck("unlock_kind")).not_to include("level")
        end
      end
    end
  end

  it "shows a guest the track with nothing granted" do
    get "/api/v1/seasons/#{season.id}/rewards", headers: api_headers

    expect(json_data["premium"]).to be(false)
    expect(json_data["current_level"]).to be_nil
    expect(json_data["levels"].filter_map { |l| l["free"] }.pluck("granted")).to all(be(false))
  end
end
