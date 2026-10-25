# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 season claims", type: :request do
  let(:user) { build_user }
  let(:season) { build_season }
  let(:participation) { SeasonProgressService.ensure_participation(user, season) }

  let(:challenge) do
    build_challenge(key: "run_20km", sport: "run", requirements: [ { metric: "distance_km", target: 20 } ])
  end

  let!(:season_challenge) do
    season.season_challenges.create!(challenge: challenge, category: "monthly", xp_reward: 500, fragment_reward: 10)
  end

  # The same path the web's claim spec takes: workouts complete the challenge,
  # and the XP waits to be collected.
  def complete_the_challenge
    participation
    ChallengeEnroller.call(user, challenge, season: season)
    3.times { |i| build_workout(user, date: Date.new(2026, 8, 3 + i), km: 8) }
    RecomputeChallengeProgress.new(user.challenge_participations.find_by(challenge: challenge, season: season)).call
    SeasonProgressService.new(participation).recalculate
    participation.reload
  end

  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

  path "/api/v1/seasons/{season_id}/claims" do
    parameter name: :season_id, in: :path, schema: { type: :integer }

    get "Finished challenges whose XP is waiting to be collected" do
      tags "Seasons"
      produces "application/json"

      response "200", "pending claims" do
        schema type: :object, required: %w[data meta], properties: {
          data: { type: :array, items: SeasonsSchemas::CLAIM },
          meta: { type: :object, required: %w[count xp], properties: { count: { type: :integer }, xp: { type: :integer } } }
        }
        let(:season_id) { season.id }
        before { complete_the_challenge }

        run_test! do
          expect(json_data.first).to include("season_challenge_id" => season_challenge.id, "xp" => 500)
          expect(json_body["meta"]).to eq("count" => 1, "xp" => 500)
        end
      end

      response "401", "signed out" do
        schema "$ref" => "#/components/schemas/error"
        let(:season_id) { season.id }
        let(:Authorization) { nil }

        run_test!
      end

      response "404", "not taking part in the season" do
        schema "$ref" => "#/components/schemas/error"
        let(:season_id) { season.id }

        run_test! { expect(json_error_code).to eq("season_not_joined") }
      end
    end

    post "Collect every pending claim" do
      tags "Seasons"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"

      response "200", "what was collected and where the bar is now" do
        schema SeasonsSchemas.data(SeasonsSchemas::CLAIM_RESULT)
        let(:season_id) { season.id }
        before { complete_the_challenge }

        run_test! do
          expect(json_data).to include("claimed" => 1, "xp_gained" => 500, "remaining" => 0)
          expect(json_data["xp"]).to eq(participation.reload.xp)
          expect(participation.xp_breakdown["challenges"]).to eq(500)
        end
      end

      response "403", "seasons switched off" do
        schema "$ref" => "#/components/schemas/error"
        let(:season_id) { season.id }
        before { FeatureFlag.set(:seasons, false) }

        run_test! { expect(json_error_code).to eq("feature_disabled") }
      end
    end
  end

  path "/api/v1/seasons/{season_id}/claims/{id}" do
    parameter name: :season_id, in: :path, schema: { type: :integer }
    parameter name: :id, in: :path, schema: { type: :integer }, description: "Completion id from GET …/claims"

    post "Collect one claim" do
      tags "Seasons"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"

      response "200", "collected" do
        schema SeasonsSchemas.data(SeasonsSchemas::CLAIM_RESULT)
        let(:season_id) { season.id }
        let(:id) { complete_the_challenge.season_challenge_completions.first.id }

        run_test! do
          expect(json_data["claimed"]).to eq(1)
          expect(SeasonChallengeCompletion.find(id)).to be_claimed
        end
      end

      response "404", "not one of mine" do
        schema "$ref" => "#/components/schemas/error"
        let(:stranger) { build_user }
        let(:season_id) { season.id }
        let(:id) { complete_the_challenge.season_challenge_completions.first.id }
        let(:Authorization) { "Bearer #{api_sign_in(stranger).access_token}" }
        before { SeasonProgressService.ensure_participation(stranger, season) }

        run_test! { expect(SeasonChallengeCompletion.find(id)).not_to be_claimed }
      end
    end
  end

  describe "never paying twice" do
    before { complete_the_challenge }

    it "pays nothing on a second claim" do
      post "/api/v1/seasons/#{season.id}/claims", headers: api_headers(user)
      xp = participation.reload.xp

      post "/api/v1/seasons/#{season.id}/claims", headers: api_headers(user)

      expect(json_data).to include("claimed" => 0, "xp_gained" => 0)
      expect(participation.reload.xp).to eq(xp)
      expect(participation.xp_breakdown["challenges"]).to eq(500)
    end

    it "replays the first answer for a retry with the same Idempotency-Key" do
      headers = api_headers(user, "Idempotency-Key" => "claim-1")

      post "/api/v1/seasons/#{season.id}/claims", headers: headers
      first = json_body

      post "/api/v1/seasons/#{season.id}/claims", headers: headers

      expect(response.headers["Idempotent-Replayed"]).to eq("true")
      expect(json_body).to eq(first)
      expect(json_data["claimed"]).to eq(1)
      expect(participation.reload.xp_breakdown["challenges"]).to eq(500)
    end

    # Two devices (or a double tap that beat the Idempotency-Key) collecting
    # the same completion at the same moment: both loaded it unclaimed, only
    # the conditional stamp decides, and the XP is recomputed from the ledger.
    it "pays once when two claims race" do
      completion_id = participation.season_challenge_completions.first.id
      stale = Array.new(2) { SeasonChallengeCompletion.find(completion_id) }

      results = stale.map do |completion|
        Thread.new do
          SeasonXpClaimer.new(SeasonParticipation.find(participation.id)).call(completion: completion)
        end
      end.map(&:value)

      expect(results.sum(&:claimed)).to eq(1)
      expect(results.sum(&:xp)).to eq(500)
      expect(participation.reload.xp_breakdown["challenges"]).to eq(500)
    end

    it "pays once when two claim-alls race" do
      results = Array.new(2) do
        Thread.new { SeasonXpClaimer.new(SeasonParticipation.find(participation.id)).call }
      end.map(&:value)

      expect(results.sum(&:claimed)).to eq(1)
      expect(participation.reload.xp_breakdown["challenges"]).to eq(500)
    end
  end

  it "refuses a season that has aged out" do
    complete_the_challenge
    season.update_columns(status: "ended")
    build_season(status: "ended", starts_at: Date.new(2026, 9, 1), ends_at: Date.new(2026, 9, 30))
    build_season(status: "active", starts_at: Date.new(2026, 10, 1), ends_at: Date.new(2026, 10, 31))

    expect { post "/api/v1/seasons/#{season.id}/claims", headers: api_headers(user) }
      .not_to change { participation.reload.xp }
    expect(response).to have_http_status(:not_found)
  end
end
