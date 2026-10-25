# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 me stats", type: :request do
  let(:user) { build_user }

  path "/api/v1/me/stats" do
    get "The numbers on the player's profile" do
      tags "Me"
      produces "application/json"

      response "200", "stats" do
        schema type: :object, required: [ "data" ], properties: { data: ProfileSchemas::STATS }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        before do
          build_workout(user, date: Date.current, km: 5.25)
          build_workout(user, date: Date.current - 1, km: 10)
          SeasonParticipation.create!(user: user, season: build_season, level: 3).update!(medal_fragments: 70)
          SeasonParticipation.create!(user: user, season: build_season, level: 1)
        end

        run_test! do
          expect(json_data).to eq(Profiles::Stats.new(user).to_h.stringify_keys)
          expect(json_data).to include("distance_km" => 15.3, "workouts" => 2, "seasons" => 2, "medals" => 1)
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }

        run_test!
      end
    end
  end
end
