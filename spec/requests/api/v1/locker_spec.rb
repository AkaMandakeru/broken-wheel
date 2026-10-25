# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 locker", type: :request do
  include ActiveJob::TestHelper

  let(:user) { build_user }
  let(:season) { build_season(status: "active", name: "Spring Season") }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

  def offer(cosmetic, claimable: true)
    season.season_rewards.create!(reward_type: "cosmetic", reward_key: cosmetic.key, name: cosmetic.name,
                                  unlock_kind: "participation", track: "free", claimable: claimable)
  end

  def join
    SeasonProgressService.ensure_participation(user, season)
  end

  path "/api/v1/me/locker" do
    get "One kind of the player's locker: owned, claimable and locked cosmetics" do
      tags "Locker"
      produces "application/json"
      parameter name: :kind, in: :query, required: false, schema: { type: :string, enum: Locker::Catalogue::KINDS, default: "banner" }

      response "200", "the locker" do
        schema type: :object, required: [ "data" ], properties: { data: ProfileSchemas::LOCKER }
        let(:kind) { "banner" }

        before do
          grant_cosmetic(user, attach_cosmetic_art(build_cosmetic(key: "cold_start", rarity: "rare")))
          user.equip_cosmetic!("banner", "cold_start")
          offer(build_cosmetic(key: "spring_banner", rarity: "epic"))
          join
          season.season_rewards.create!(reward_type: "cosmetic", reward_key: build_cosmetic(key: "summit").key,
                                        name: "Summit", unlock_kind: "level", level: 12, unlock_value: 12)
          build_cosmetic(key: "nowhere_yet", rarity: "legendary")
          build_cosmetic(key: "a_frame", kind: "frame")
        end

        run_test! do
          locker = json_data
          expect(locker).to include("kind" => "banner", "equipped_key" => "cold_start", "kinds" => %w[banner frame])
          expect(locker["owned"].map { |c| c.values_at("key", "equipped") }).to eq([ [ "cold_start", true ] ])
          expect(locker.dig("owned", 0, "image")).to include("display")
          expect(locker["claimable"].map { |c| [ c["key"], c.dig("season", "name") ] }).to eq([ %w[spring_banner Spring\ Season] ])

          locked = locker["locked"].index_by { |c| c["key"] }
          expect(locked.keys).to contain_exactly("summit", "nowhere_yet")
          expect(locked.dig("summit", "unlock")).to include("unlock_kind" => "level", "unlock_value" => 12, "label" => "Level 12")
          expect(locked.dig("nowhere_yet", "unlock")).to be_nil
          # No art yet: the app draws the same rarity gradient as the web.
          expect(locked.dig("nowhere_yet", "render")).to eq(
            "type" => "gradient", "colors" => CosmeticStyle::PALETTE.values_at("amber-400", "orange-500", "amber-600")
          )
        end
      end

      response "400", "not a locker kind" do
        schema "$ref" => "#/components/schemas/error"
        let(:kind) { "outfit" }

        run_test! do
          expect(json_error_code).to eq("invalid_kind")
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }
        let(:kind) { "banner" }

        run_test!
      end
    end
  end

  path "/api/v1/me/locker/{kind}" do
    parameter name: :kind, in: :path, schema: { type: :string, enum: Locker::Catalogue::KINDS }

    put "Wear a cosmetic the player owns" do
      tags "Locker"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: { type: :object, required: [ "key" ], properties: { key: { type: :string } } }

      response "200", "equipped; the updated locker" do
        schema type: :object, required: [ "data" ], properties: { data: ProfileSchemas::LOCKER }
        let(:kind) { "frame" }
        let(:body) { { key: "steel_rim" } }

        before { grant_cosmetic(user, build_cosmetic(key: "steel_rim", kind: "frame")) }

        run_test! do
          expect(json_data["equipped_key"]).to eq("steel_rim")
          expect(user.reload.equipped["frame"]).to eq("steel_rim")
        end
      end

      response "422", "not owned, not wearable, or does not exist — deliberately indistinguishable" do
        schema "$ref" => "#/components/schemas/error"
        let(:kind) { "banner" }
        let(:body) { { key: "summer_heat" } }

        before { build_cosmetic(key: "summer_heat") }

        run_test! do
          expect(json_error_code).to eq("cosmetic_unavailable")
          expect(user.reload.equipped["banner"]).to be_nil
        end
      end

      response "404", "not a locker kind" do
        schema "$ref" => "#/components/schemas/error"
        let(:kind) { "outfit" }
        let(:body) { { key: "anything" } }

        run_test!
      end
    end

    delete "Take off whatever is worn in this slot" do
      tags "Locker"
      produces "application/json"

      response "200", "removed; the updated locker" do
        schema type: :object, required: [ "data" ], properties: { data: ProfileSchemas::LOCKER }
        let(:kind) { "banner" }

        before do
          grant_cosmetic(user, build_cosmetic(key: "cold_start"))
          grant_cosmetic(user, build_cosmetic(key: "steel_rim", kind: "frame"))
          user.equip_cosmetic!("banner", "cold_start")
          user.equip_cosmetic!("frame", "steel_rim")
        end

        run_test! do
          expect(json_data["equipped_key"]).to be_nil
          expect(user.reload.equipped["banner"]).to be_nil
          expect(user.equipped["frame"]).to eq("steel_rim")
        end
      end
    end
  end

  path "/api/v1/me/locker/claim" do
    post "Take a cosmetic a season is offering" do
      tags "Locker"
      consumes "application/json"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"
      parameter name: :body, in: :body, schema: { type: :object, required: [ "key" ], properties: { key: { type: :string } } }

      let!(:banner) { build_cosmetic(key: "spring_banner", rarity: "epic") }

      response "201", "claimed" do
        schema type: :object, required: [ "data" ], properties: { data: ProfileSchemas::CLAIM }
        let(:body) { { key: "spring_banner" } }

        before do
          offer(banner)
          join
        end

        run_test! do
          expect(json_data["status"]).to eq("claimed")
          expect(json_data.dig("cosmetic", "key")).to eq("spring_banner")
          expect(user.reload.owns_cosmetic?("spring_banner")).to be(true)
        end
      end

      response "200", "already owned" do
        schema type: :object, required: [ "data" ], properties: { data: ProfileSchemas::CLAIM }
        let(:body) { { key: "spring_banner" } }

        before { grant_cosmetic(user, banner) }

        run_test! do
          expect(json_data["status"]).to eq("already_owned")
        end
      end

      response "422", "not on offer to this player" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { key: "spring_banner" } }

        before { offer(banner) } # never joined the season

        run_test! do
          expect(json_error_code).to eq("cosmetic_unavailable")
          expect(user.reload.owns_cosmetic?("spring_banner")).to be(false)
        end
      end
    end
  end

  describe "claiming" do
    let!(:banner) { build_cosmetic(key: "spring_banner", rarity: "epic") }

    before do
      offer(banner)
      join
    end

    it "grants once for a retried request with the same Idempotency-Key" do
      headers = api_headers(user, "Idempotency-Key" => "claim-1")

      2.times { post "/api/v1/me/locker/claim", params: { key: "spring_banner" }, headers: headers, as: :json }

      expect(response).to have_http_status(:created)
      expect(response.headers["Idempotent-Replayed"]).to eq("true")
      expect(user.user_cosmetics.where(cosmetic: banner).count).to eq(1)
    end

    it "moves the cosmetic from claimable to owned" do
      post "/api/v1/me/locker/claim", params: { key: "spring_banner" }, headers: api_headers(user), as: :json
      get "/api/v1/me/locker", headers: api_headers(user)

      expect(json_data["claimable"]).to be_empty
      expect(json_data["owned"].pluck("key")).to eq([ "spring_banner" ])
    end

    it "lists frames separately from banners" do
      get "/api/v1/me/locker", params: { kind: "frame" }, headers: api_headers(user)

      expect(json_data).to include("kind" => "frame", "claimable" => [], "owned" => [])
    end
  end

  it "answers the same whether a key is unowned or does not exist at all" do
    build_cosmetic(key: "real_one")

    put "/api/v1/me/locker/banner", params: { key: "real_one" }, headers: api_headers(user), as: :json
    real = [ response.status, json_body ]
    put "/api/v1/me/locker/banner", params: { key: "made_up" }, headers: api_headers(user), as: :json

    expect([ response.status, json_body ]).to eq(real)
  end
end
