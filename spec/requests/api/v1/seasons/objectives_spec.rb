# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 season objectives", type: :request do
  before { travel_to Time.utc(2026, 8, 15, 12) }
  after { travel_back }

  let(:user) { build_user }
  let!(:season) { Seasons::BlueprintImporter.call("season_8_legacy_of_champions") }

  path "/api/v1/seasons/{season_id}/objectives" do
    parameter name: :season_id, in: :path, schema: { type: :integer }

    get "Season objectives and the legacy missions track" do
      tags "Seasons"
      security [ {}, { bearer: [] } ]
      produces "application/json"

      response "200", "objectives" do
        schema SeasonsSchemas.data(
          type: :object, required: %w[objectives legacy_missions],
          properties: {
            objectives: { type: :array, items: SeasonsSchemas::OBJECTIVE },
            legacy_missions: {
              type: :object, required: %w[completed_count total missions],
              properties: {
                completed_count: { type: :integer },
                total: { type: :integer },
                missions: { type: :array, items: SeasonsSchemas::OBJECTIVE }
              }
            }
          }
        )
        let(:season_id) { season.id }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        before do
          participation = SeasonProgressService.ensure_participation(user, season)
          participation.season_objective_completions.create!(
            season_objective: season.season_objectives.legacy.first, completed_at: Time.current, xp_awarded: 100
          )
        end

        run_test! do
          legacy = json_data["legacy_missions"]
          expect(legacy["total"]).to eq(5)
          expect(legacy["completed_count"]).to eq(1)
          expect(legacy["missions"].first).to include("completed" => true, "track" => "legacy")
          expect(legacy["missions"].first["title"]).to eq(I18n.t("seasons.legacy.#{season.season_objectives.legacy.first.name}.title"))
        end
      end
    end
  end
end
