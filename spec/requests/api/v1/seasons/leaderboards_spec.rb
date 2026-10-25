# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 season leaderboard", type: :request do
  let(:user) { build_user(first_name: "Me") }
  let!(:season) { build_season }

  def join(player, **stats)
    SeasonProgressService.ensure_participation(player, season).tap { |p| p.update_columns(**stats) }
  end

  path "/api/v1/seasons/{season_id}/leaderboard" do
    parameter name: :season_id, in: :path, schema: { type: :integer }
    parameter name: :board, in: :query, required: false,
              schema: { type: :string, enum: SeasonLeaderboard.boards.map(&:to_s), default: "xp" }

    get "One leaderboard: the top ten and my position" do
      tags "Seasons"
      security [ {}, { bearer: [] } ]
      produces "application/json"

      response "200", "the board" do
        schema SeasonsSchemas.data(SeasonsSchemas::LEADERBOARD)
        let(:season_id) { season.id }
        let(:board) { "distance" }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        before do
          11.times { |i| join(build_user, total_distance_km: 100 + i) }
          join(user, total_distance_km: 50)
        end

        run_test! do
          expect(json_data["board"]).to eq("distance")
          expect(json_data["unit"]).to eq("km")
          expect(json_data["rows"].size).to eq(10)
          expect(json_data["rows"].first).to include("position" => 1, "value" => 110.0, "me" => false)
          expect(json_data["me"]).to eq("position" => 12, "value" => 50.0)
        end
      end
    end
  end

  it "falls back to the XP board for an unknown one, as the web does" do
    join(user, xp: 300)

    get "/api/v1/seasons/#{season.id}/leaderboard", params: { board: "nope" }, headers: api_headers(user)

    expect(json_data["board"]).to eq("xp")
    expect(json_data["rows"].first).to include("me" => true, "value" => 300.0)
  end

  it "has no position for a guest" do
    get "/api/v1/seasons/#{season.id}/leaderboard", headers: api_headers

    expect(json_data["me"]).to be_nil
  end
end
