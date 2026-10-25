# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 season activities", type: :request do
  let(:user) { build_user(first_name: "Ana") }
  let!(:season) { build_season }

  path "/api/v1/seasons/{season_id}/activities" do
    parameter name: :season_id, in: :path, schema: { type: :integer }
    parameter "$ref" => "#/components/parameters/cursor"
    parameter "$ref" => "#/components/parameters/limit"

    get "The season's activity feed, newest first" do
      tags "Seasons"
      security [ {}, { bearer: [] } ]
      produces "application/json"

      response "200", "a page of activity" do
        schema type: :object, required: %w[data meta], properties: {
          data: { type: :array, items: SeasonsSchemas::ACTIVITY },
          meta: { "$ref" => "#/components/schemas/page_meta" }
        }
        let(:season_id) { season.id }
        let(:limit) { 2 }

        before do
          season.season_activities.create!(user: user, kind: "level_up", metadata: { "level" => 2 })
          season.season_activities.create!(kind: "community_milestone", metadata: { "percent" => 25, "goal" => "Marathon" })
          season.season_activities.create!(user: user, kind: "level_up", metadata: { "level" => 3 })
        end

        run_test! do
          expect(json_data.size).to eq(2)
          expect(json_data.first).to include("kind" => "level_up", "text" => I18n.t("seasons.activity.level_up", level: 3))
          expect(json_data.first.dig("user", "first_name")).to eq("Ana")
          expect(json_data.second).to include("community" => true, "user" => nil)
          expect(json_body.dig("meta", "next_cursor")).to be_present
        end
      end
    end
  end

  it "walks the whole feed page by page" do
    5.times { |i| season.season_activities.create!(user: user, kind: "level_up", metadata: { "level" => i + 2 }) }

    ids = []
    cursor = nil
    loop do
      get "/api/v1/seasons/#{season.id}/activities", params: { limit: 2, cursor: cursor }.compact, headers: api_headers
      ids.concat(json_data.pluck("id"))
      cursor = json_body.dig("meta", "next_cursor")
      break if cursor.nil?
    end

    expect(ids).to eq(season.season_activities.order(created_at: :desc, id: :desc).pluck(:id))
  end
end
