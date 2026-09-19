# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seasons", type: :request do
  # Season 8 runs 1-31 August 2026, and several of these examples only hold
  # inside that window: DailyChallenges::Assigner draws nothing outside it, so
  # the "Today" section stops rendering altogether. Unpinned, they passed in
  # August and failed every month after — which is exactly what happened on
  # 1 September. Declared above the let! so the clock moves before the import.
  before { travel_to Time.utc(2026, 8, 15, 12) }
  after { travel_back }

  let(:user) { build_user }
  let!(:season) { Seasons::BlueprintImporter.call("season_8_legacy_of_champions") }

  describe "GET /seasons/:id" do
    it "renders for a guest" do
      get season_path(season)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(season.name)
      expect(response.body).to include(ERB::Util.html_escape(season.slogan))
    end

    it "renders every section for a signed-in participant" do
      sign_in user
      get season_path(season)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.show.battle_pass")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.show.today")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.show.legacy_missions")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.show.leaderboard")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.community.goals.august_marathon.title")))
    end

    it "renders in Portuguese" do
      sign_in user
      get season_path(season, locale: :pt), headers: { "Accept-Language" => "pt" }

      expect(response).to have_http_status(:ok)
    end

    # These used to be secrets, withheld until a player stumbled into completing
    # one. They are on the board from the start now, under their own heading.
    it "lists special challenges before they are completed" do
      sign_in user
      get season_path(season)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("challenges.defaults.s8_secret_early_bird.title")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.categories.special")))
    end

    it "shows a special challenge to a signed-out visitor too" do
      get season_path(season)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("challenges.defaults.s8_secret_early_bird.title")))
    end

    # The second column: special challenges lead it, the legacy missions follow.
    # In the first column they sat under the weekly run and got lost.
    it "puts special challenges in the second column, above the legacy missions" do
      sign_in user
      get season_path(season)

      special_section = response.body.index("fa-star text-purple-500")
      legacy_section = response.body.index(ERB::Util.html_escape(I18n.t("seasons.show.legacy_missions")))

      expect(special_section).to be_present
      expect(legacy_section).to be_present
      expect(special_section).to be < legacy_section
    end

    it "no longer lists special challenges among the first column's categories" do
      sign_in user
      get season_path(season)

      # The first column renders its categories as small uppercase h3s; the
      # special section is an h2 in the second column.
      first_column_heading = %(uppercase tracking-wide mt-6 mb-2">\n          <i class="fa-solid fa-star)
      expect(response.body).not_to include(first_column_heading)
    end

    it "marks a special challenge as special" do
      sign_in user
      special = season.season_challenges.special.first

      get season_path(season)

      expect(special.category).to eq("special")
      expect(response.body).to include(ERB::Util.html_escape(special.challenge.display_title))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.show.special")))
    end

    it "switches leaderboard boards" do
      sign_in user

      SeasonLeaderboard.boards.each do |board|
        get season_path(season, board: board)
        expect(response).to have_http_status(:ok), "board #{board} failed to render"
      end
    end

    it "assigns three dailies on first visit and keeps them stable" do
      sign_in user

      get season_path(season)
      first = DailyChallengeAssignment.where(user: user).pluck(:daily_challenge_template_id).sort
      expect(first.size).to eq(3)

      get season_path(season)
      expect(DailyChallengeAssignment.where(user: user).pluck(:daily_challenge_template_id).sort).to eq(first)
    end

    it "shows compound requirements on a weekly challenge card" do
      sign_in user
      get season_path(season)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("challenges.requirements.distance_km", target: 15)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("challenges.requirements.activity_count", count: 4)))
    end

    it "marks elite challenges as locked below the unlock level" do
      sign_in user
      unlock_level = season.season_challenges.of_category("elite").first.unlock_level

      get season_path(season)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.show.unlocks_at_level", level: unlock_level)))
    end
  end

  describe "GET /seasons" do
    it "lists active seasons" do
      get seasons_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(season.name)
    end
  end

  # A finished season nobody can still affect is a dead leaderboard, so players
  # get exactly one step back and no further.
  describe "how far back a player can look" do
    let!(:last_season) do
      build_season(name: "Last Season", status: "ended",
                   starts_at: Date.new(2026, 7, 1), ends_at: Date.new(2026, 7, 31))
    end

    let!(:older_season) do
      build_season(name: "Older Season", status: "ended",
                   starts_at: Date.new(2026, 6, 1), ends_at: Date.new(2026, 6, 30))
    end

    before { season.update!(status: "active") }

    it "opens the most recent finished season" do
      get season_path(last_season)

      expect(response).to have_http_status(:ok)
    end

    it "closes anything older than that" do
      get season_path(older_season)

      expect(response).to redirect_to(seasons_path)
      expect(flash[:alert]).to eq(I18n.t("flashes.seasons.archived"))
    end

    it "closes it for a signed-in player too" do
      sign_in user

      get season_path(older_season)

      expect(response).to redirect_to(seasons_path)
    end

    it "lists only one past season" do
      get seasons_path

      expect(response.body).to include("Last Season")
      expect(response.body).not_to include("Older Season")
    end

    # The admin panel links straight to the public page, so that link has to keep
    # resolving for a season players can no longer open.
    it "still opens for an admin" do
      sign_in build_user(admin: true)

      get season_path(older_season)

      expect(response).to have_http_status(:ok)
    end

    it "leaves the active season alone" do
      get season_path(season)

      expect(response).to have_http_status(:ok)
    end
  end
end
