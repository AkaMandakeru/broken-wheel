# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 achievements", type: :request do
  let(:user) { build_user }

  def participate(season, fragments:, level: 1, completion: 0)
    SeasonParticipation.create!(user: user, season: season, level: level).tap do |participation|
      participation.update!(medal_fragments: fragments, completion_percent: completion)
    end
  end

  path "/api/v1/achievements" do
    get "Season medals, medal counts and season reward badges" do
      tags "Achievements"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/accept_language"

      response "200", "the medal shelf" do
        schema type: :object, required: [ "data" ], properties: { data: ProfileSchemas::ACHIEVEMENTS }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        before do
          participate(build_season(name: "Gold Season", status: "ended", starts_at: 2.months.ago, ends_at: 1.month.ago),
                      fragments: 130, level: 20, completion: 88)
          participate(build_season(name: "Rookie Season", status: "active"), fragments: 4, level: 2, completion: 5)
          badge = Badge.create!(name: "Season Finisher", icon: "🏁", badge_type: "season")
          user.user_badges.create!(badge: badge, earned_at: 1.day.ago)
        end

        run_test! do
          shelf = json_data
          expect(shelf).to include("seasons_played" => 2, "medals_earned" => 1, "fragments" => 134)
          expect(shelf["medal_counts"]).to eq("bronze" => 0, "silver" => 0, "gold" => 1, "diamond" => 0)

          gold = shelf["seasons"].find { |entry| entry.dig("season", "name") == "Gold Season" }
          expect(gold).to include("medal_tier" => "gold", "medal_label" => "Gold", "next_medal_tier" => "diamond",
                                  "fragments_to_next_medal" => 70, "level" => 20, "completion_percent" => 88)
          rookie = shelf["seasons"].find { |entry| entry.dig("season", "name") == "Rookie Season" }
          expect(rookie).to include("medal_tier" => nil, "next_medal_tier" => "bronze")
          expect(rookie.dig("season", "browsable")).to be(true)

          expect(shelf["reward_badges"].pluck("name")).to eq([ "Season Finisher" ])
        end
      end

      response "403", "achievements are switched off" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        before do
          FeatureFlag.set(:achievements, false)
          Features.reset_cache
        end

        after { Features.reset_cache }

        run_test! do
          expect(json_error_code).to eq("feature_disabled")
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }

        run_test!
      end
    end
  end

  it "is an empty shelf for someone who never played a season" do
    get "/api/v1/achievements", headers: api_headers(user)

    expect(json_data).to include("seasons_played" => 0, "medals_earned" => 0, "seasons" => [], "reward_badges" => [])
  end
end
