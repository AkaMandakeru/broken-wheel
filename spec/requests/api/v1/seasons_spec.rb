# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 seasons", type: :request do
  # Inside the season's own window, so dailies and the board behave as live.
  before { travel_to Time.utc(2026, 8, 15, 12) }
  after { travel_back }

  let(:user) { build_user }
  let!(:season) { build_season(name: "August", slogan: "Go") }

  path "/api/v1/seasons" do
    get "List the running seasons and the one still open to look back on" do
      tags "Seasons"
      security [ {}, { bearer: [] } ]
      produces "application/json"

      response "200", "seasons" do
        schema SeasonsSchemas.data(
          type: :object, required: %w[active archive],
          properties: {
            active: { type: :array, items: SeasonsSchemas::SEASON },
            archive: { type: :array, items: SeasonsSchemas::SEASON }
          }
        )

        let!(:last_season) { build_season(name: "July", status: "ended", starts_at: Date.new(2026, 7, 1), ends_at: Date.new(2026, 7, 31)) }
        let!(:older_season) { build_season(name: "June", status: "ended", starts_at: Date.new(2026, 6, 1), ends_at: Date.new(2026, 6, 30)) }

        run_test! do
          expect(json_data["active"].pluck("name")).to eq([ "August" ])
          expect(json_data["archive"].pluck("name")).to eq([ "July" ])
        end
      end

      response "403", "seasons switched off" do
        schema "$ref" => "#/components/schemas/error"
        before { FeatureFlag.set(:seasons, false) }

        run_test! { expect(json_error_code).to eq("feature_disabled") }
      end
    end
  end

  path "/api/v1/seasons/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }

    get "A season: header, my standing, banner state and the next special event" do
      tags "Seasons"
      description "Viewing an active season enrolls the signed-in player, as the web page does."
      security [ {}, { bearer: [] } ]
      produces "application/json"

      response "200", "the season" do
        schema SeasonsSchemas.data(SeasonsSchemas::OVERVIEW)
        let(:id) { season.id }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        run_test! do
          expect(json_data.dig("season", "name")).to eq("August")
          expect(json_data.dig("season", "level_curve").size).to eq(30)
          expect(json_data.dig("participation", "level")).to eq(1)
          expect(json_data["announcement"]).to eq("visible" => false, "dismissed" => false)
          expect(user.season_participations.where(season: season)).to exist
        end
      end

      response "404", "a season players can no longer open" do
        schema "$ref" => "#/components/schemas/error"
        let(:id) do
          build_season(status: "ended", starts_at: Date.new(2026, 7, 1), ends_at: Date.new(2026, 7, 31))
          build_season(status: "ended", starts_at: Date.new(2026, 6, 1), ends_at: Date.new(2026, 6, 30)).id
        end

        run_test! { expect(json_error_code).to eq("not_found") }
      end
    end
  end

  describe "GET /api/v1/seasons/:id" do
    it "shows a guest the season without enrolling anyone" do
      expect { get "/api/v1/seasons/#{season.id}", headers: api_headers }
        .not_to change(SeasonParticipation, :count)

      expect(response).to have_http_status(:ok)
      expect(json_data["participation"]).to be_nil
      expect(json_data["announcement"]).to be_nil
    end

    it "does not enroll anyone in a season that hasn't started" do
      upcoming = build_season(status: "upcoming", starts_at: Date.new(2026, 9, 1), ends_at: Date.new(2026, 9, 30))

      get "/api/v1/seasons/#{upcoming.id}", headers: api_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json_data["participation"]).to be_nil
    end

    it "opens an aged-out season for an admin" do
      build_season(status: "ended", starts_at: Date.new(2026, 7, 1), ends_at: Date.new(2026, 7, 31))
      old = build_season(status: "ended", starts_at: Date.new(2026, 6, 1), ends_at: Date.new(2026, 6, 30))

      get "/api/v1/seasons/#{old.id}", headers: api_headers(build_user(admin: true))

      expect(response).to have_http_status(:ok)
    end

    it "reports the banner as visible until it is dismissed" do
      season.update_columns(announced_at: 1.day.ago)

      get "/api/v1/seasons/#{season.id}", headers: api_headers(user)
      expect(json_data["announcement"]).to eq("visible" => true, "dismissed" => false)

      user.dismiss_season_announcement(season.id)
      get "/api/v1/seasons/#{season.id}", headers: api_headers(user)
      expect(json_data["announcement"]).to eq("visible" => false, "dismissed" => true)
    end

    describe "the next special event" do
      def add_special(key, on:)
        challenge = build_challenge(key: key, requirements: [ { metric: "activity_count", target: 1 } ])
        season.season_challenges.create!(challenge: challenge, category: "special", xp_reward: 300,
                                         starts_at: on, ends_at: on)
      end

      it "is the soonest special that hasn't happened yet" do
        add_special("past_event", on: Date.new(2026, 8, 10))
        later = add_special("later_event", on: Date.new(2026, 8, 28))
        sooner = add_special("sooner_event", on: Date.new(2026, 8, 20))
        all_season = build_challenge(key: "all_season", requirements: [ { metric: "activity_count", target: 30 } ])
        season.season_challenges.create!(challenge: all_season, category: "special")

        get "/api/v1/seasons/#{season.id}", headers: api_headers(user)

        event = json_data["next_special_event"]
        expect(event["id"]).to eq(sooner.id)
        expect(event).to include("special" => true, "starts_on" => "2026-08-20", "narrower_than_season" => true)
        expect(later.id).not_to eq(event["id"])
      end

      it "counts an event happening today" do
        today = add_special("today_event", on: Date.new(2026, 8, 15))

        get "/api/v1/seasons/#{season.id}", headers: api_headers

        expect(json_data.dig("next_special_event", "id")).to eq(today.id)
      end

      it "is null when none is left" do
        add_special("past_event", on: Date.new(2026, 8, 10))

        get "/api/v1/seasons/#{season.id}", headers: api_headers

        expect(json_data["next_special_event"]).to be_nil
      end
    end

    describe "HTTP caching" do
      it "answers 304 while nothing has changed" do
        headers = api_headers(user)
        get "/api/v1/seasons/#{season.id}", headers: headers
        etag = response.headers["ETag"]
        expect(etag).to be_present

        get "/api/v1/seasons/#{season.id}", headers: headers.merge("If-None-Match" => etag)
        expect(response).to have_http_status(:not_modified)
      end

      it "changes once the player's progress moves" do
        headers = api_headers(user)
        get "/api/v1/seasons/#{season.id}", headers: headers
        etag = response.headers["ETag"]

        travel 1.second
        SeasonParticipation.find_by(user: user, season: season).update!(xp: 500)

        get "/api/v1/seasons/#{season.id}", headers: headers.merge("If-None-Match" => etag)
        expect(response).to have_http_status(:ok)
        expect(json_data.dig("participation", "xp")).to eq(500)
      end

      it "differs per language" do
        get "/api/v1/seasons/#{season.id}", headers: api_headers(user)
        etag = response.headers["ETag"]

        get "/api/v1/seasons/#{season.id}", headers: api_headers(user, "Accept-Language" => "pt", "If-None-Match" => etag)
        expect(response).to have_http_status(:ok)
        expect(json_data.dig("season", "status_label")).to eq(I18n.t("seasons.statuses.active", locale: :pt))
      end
    end
  end
end
