# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 challenges", type: :request do
  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
  let(:challenge) { build_challenge(key: "august_50k", requirements: [ { metric: "distance_km", target: 50 } ], sport: "run") }

  path "/api/v1/challenges" do
    get "Active challenges, newest first, with the viewer's participation" do
      tags "Challenges"
      produces "application/json"
      parameter name: :type, in: :query, required: false, schema: { type: :string, enum: Challenge::CHALLENGE_TYPES }

      response "200", "challenges" do
        schema SocialSchemas.list(SocialSchemas::CHALLENGE)
        let(:type) { nil }

        before do
          ChallengeEnroller.call(user, challenge)
          build_challenge(key: "other_one", requirements: [ { metric: "activity_count", target: 3 } ]).update!(challenge_type: "weekly")
          Challenge.create!(title: "Finished", status: "completed")
        end

        run_test! do
          expect(json_data.pluck("title")).to contain_exactly("August 50k", "Other one")
          joined = json_data.find { |item| item["id"] == challenge.id }
          expect(joined["my_participation"]).to include("season_id" => nil, "completed" => false)
          expect(joined["requirements"].first).to include("metric" => "distance_km", "target" => 50.0)
        end
      end

      response "200", "filtered by type" do
        schema SocialSchemas.list(SocialSchemas::CHALLENGE)
        let(:type) { "weekly" }

        before do
          challenge
          build_challenge(key: "weekly_one", requirements: [ { metric: "activity_count", target: 3 } ]).update!(challenge_type: "weekly")
        end

        run_test! do
          expect(json_data.pluck("key")).to eq([ "weekly_one" ])
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }
        let(:type) { nil }

        run_test!
      end

      response "403", "challenges are switched off" do
        schema "$ref" => "#/components/schemas/error"
        let(:type) { nil }

        before { FeatureFlag.set(:challenges, false) }

        run_test! do
          expect(json_error_code).to eq("feature_disabled")
        end
      end
    end
  end

  path "/api/v1/challenges/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }

    get "One challenge: requirements, the viewer's progress and the ranking" do
      tags "Challenges"
      produces "application/json"

      response "200", "the challenge" do
        schema SocialSchemas.data(SocialSchemas::CHALLENGE_DETAIL)
        let(:id) { challenge.id }

        before do
          ChallengeEnroller.call(user, challenge).update!(progress_value: 10)
          ChallengeEnroller.call(build_user(first_name: "Bia"), challenge).update!(progress_value: 30)
        end

        run_test! do
          expect(json_data["season"]).to be_nil
          expect(json_data["my_participation"]["progress_value"]).to eq(10.0)
          expect(json_data["ranking"].map { |row| [ row["rank"], row["user"]["first_name"], row["me"] ] })
            .to eq([ [ 1, "Bia", false ], [ 2, "Test", true ] ])
        end
      end

      response "404", "no such challenge" do
        schema "$ref" => "#/components/schemas/error"
        let(:id) { 0 }

        run_test!
      end
    end
  end

  it "reads progress and ranking in the challenge's active season, like the web page" do
    season = build_season
    SeasonChallenge.create!(season: season, challenge: challenge)
    ChallengeEnroller.call(user, challenge).update!(progress_value: 99)
    ChallengeEnroller.call(user, challenge, season: season).update!(progress_value: 7)

    get "/api/v1/challenges/#{challenge.id}", headers: api_headers(user)

    expect(json_data["season"]).to eq("id" => season.id, "name" => season.name)
    expect(json_data["my_participation"]).to include("season_id" => season.id, "progress_value" => 7.0)
    expect(json_data["ranking"].pluck("progress_value")).to eq([ 7.0 ])
  end

  path "/api/v1/challenges/{id}/join" do
    parameter name: :id, in: :path, schema: { type: :integer }

    post "Join a challenge" do
      tags "Challenges"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"

      response "201", "joined" do
        schema SocialSchemas.data(SocialSchemas::CHALLENGE_DETAIL)
        let(:id) { challenge.id }

        run_test! do
          expect(json_data["my_participation"]).to be_present
          expect(user.challenge_participations.where(challenge: challenge).count).to eq(1)
        end
      end

      response "409", "already joined" do
        schema "$ref" => "#/components/schemas/error"
        let(:id) { challenge.id }

        before { ChallengeEnroller.call(user, challenge) }

        run_test! do
          expect(json_error_code).to eq("already_joined")
        end
      end
    end
  end

  it "back-fills workouts and tracks the join like the web" do
    build_workout(user, date: Date.new(2026, 8, 3), km: 12)
    allow(Analytics).to receive(:track)

    post "/api/v1/challenges/#{challenge.id}/join", headers: api_headers(user)

    expect(json_data["my_participation"]["progress_value"]).to eq(12.0)
    expect(Analytics).to have_received(:track).with(hash_including(event: "challenge_joined"))
  end

  it "replays a retried join instead of answering 409" do
    headers = api_headers(user, "Idempotency-Key" => "join-1")
    post "/api/v1/challenges/#{challenge.id}/join", headers: headers
    post "/api/v1/challenges/#{challenge.id}/join", headers: headers

    expect(response).to have_http_status(:created)
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
  end

  path "/api/v1/challenges/{id}/invite" do
    parameter name: :id, in: :path, schema: { type: :integer }

    get "A link to invite friends (requires having joined)" do
      tags "Challenges"
      produces "application/json"

      response "200", "the invite" do
        schema SocialSchemas.data(SocialSchemas::CHALLENGE_INVITE)
        let(:id) { challenge.id }
        let!(:participation) { ChallengeEnroller.call(user, challenge) }

        run_test! do
          expect(json_data["invite_code"]).to eq(participation.invite_code)
          expect(json_data["url"]).to end_with("/challenges/#{challenge.id}")
        end
      end

      response "403", "not joined" do
        schema "$ref" => "#/components/schemas/error"
        let(:id) { challenge.id }

        run_test! do
          expect(json_error_code).to eq("must_join_first")
        end
      end
    end
  end
end
