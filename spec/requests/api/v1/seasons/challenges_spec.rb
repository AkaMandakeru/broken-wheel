# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 season challenges", type: :request do
  before { travel_to Time.utc(2026, 8, 15, 12) }
  after { travel_back }

  let(:user) { build_user }
  let!(:season) { Seasons::BlueprintImporter.call("season_8_legacy_of_champions") }

  path "/api/v1/seasons/{season_id}/challenges" do
    parameter name: :season_id, in: :path, schema: { type: :integer }

    get "The season board, by section, with my progress per challenge and requirement" do
      tags "Seasons"
      security [ {}, { bearer: [] } ]
      produces "application/json"

      response "200", "challenge sections" do
        schema SeasonsSchemas.data(
          type: :object, required: [ "sections" ],
          properties: {
            sections: {
              type: :array,
              items: {
                type: :object, required: %w[category label challenges],
                properties: {
                  category: { type: :string, enum: SeasonChallenge::CATEGORIES },
                  label: { type: :string },
                  challenges: { type: :array, items: SeasonsSchemas::CHALLENGE }
                }
              }
            }
          }
        )
        let(:season_id) { season.id }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        before { SeasonProgressService.ensure_participation(user, season) }

        run_test! do
          sections = json_data["sections"]
          expect(sections.pluck("category")).to eq(%w[weekly monthly elite special])
          expect(sections.first["challenges"].pluck("week_index")).to eq([ 1, 2, 3, 4 ])

          weekly = sections.first["challenges"].first
          expect(weekly["requirements"].pluck("medal").first(3)).to eq(%w[bronze silver gold])
          expect(weekly["progress"]).to include("completed" => false)
          expect(weekly["requirements"].first["progress"]).to include("met" => false)

          elite = sections.find { |s| s["category"] == "elite" }["challenges"].first
          expect(elite).to include("locked" => true, "unlock_level" => 7)
        end
      end

      response "404", "unknown season" do
        schema "$ref" => "#/components/schemas/error"
        let(:season_id) { 0 }

        run_test!
      end
    end
  end

  it "shows a guest the board without progress" do
    get "/api/v1/seasons/#{season.id}/challenges", headers: api_headers

    challenge = json_data["sections"].first["challenges"].first
    expect(challenge["progress"]).to be_nil
    expect(challenge["requirements"].first["progress"]).to be_nil
    expect(challenge["locked"]).to be(false)
  end

  it "marks the weekly medal earned once a requirement is met" do
    participation = SeasonProgressService.ensure_participation(user, season)
    week = season.season_challenges.find_by(week_index: 3)
    first_requirement = week.challenge.challenge_requirements.first
    user.challenge_participations.find_by(challenge: week.challenge, season: season)
        .update!(requirement_progress: { first_requirement.id.to_s => first_requirement.target })

    get "/api/v1/seasons/#{season.id}/challenges", headers: api_headers(user)

    card = json_data["sections"].first["challenges"].find { |c| c["id"] == week.id }
    expect(card.dig("progress", "medal")).to eq("bronze")
    expect(card["requirements"].first.dig("progress", "met")).to be(true)
    expect(participation).to be_persisted
  end

  it "answers 304 until the player's progress moves" do
    SeasonProgressService.ensure_participation(user, season)
    headers = api_headers(user)
    get "/api/v1/seasons/#{season.id}/challenges", headers: headers
    etag = response.headers["ETag"]

    get "/api/v1/seasons/#{season.id}/challenges", headers: headers.merge("If-None-Match" => etag)
    expect(response).to have_http_status(:not_modified)

    travel 1.second
    user.challenge_participations.where(season: season).first.update!(progress_value: 3)
    get "/api/v1/seasons/#{season.id}/challenges", headers: headers.merge("If-None-Match" => etag)
    expect(response).to have_http_status(:ok)
  end
end
