# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 season community goal", type: :request do
  before { travel_to Time.utc(2026, 8, 15, 12) }
  after { travel_back }

  let!(:season) { Seasons::BlueprintImporter.call("season_8_legacy_of_champions") }

  path "/api/v1/seasons/{season_id}/community" do
    parameter name: :season_id, in: :path, schema: { type: :integer }

    get "The community goal, its current tier and milestones" do
      tags "Seasons"
      security [ {}, { bearer: [] } ]
      produces "application/json"

      response "200", "the goal (null when the season has none)" do
        schema SeasonsSchemas.data(SeasonsSchemas::COMMUNITY_GOAL)
        let(:season_id) { season.id }

        before { season.season_community_goals.first.update!(current_value: 1234) }

        run_test! do
          goal = season.season_community_goals.first
          expect(json_data).to include(
            "key" => goal.key, "title" => I18n.t("seasons.community.goals.august_marathon.title"), "tier" => 1
          )
          expect(json_data["progress"]).to eq(1234.0)
          expect(json_data["milestones"].size).to eq(goal.current_milestones.count)
        end
      end
    end
  end

  it "is null for a season without one" do
    get "/api/v1/seasons/#{build_season(name: 'Bare').id}/community", headers: api_headers

    expect(response).to have_http_status(:ok)
    expect(json_body).to eq("data" => nil)
  end
end
