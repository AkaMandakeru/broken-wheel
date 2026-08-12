# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Seasons", type: :request do
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

    # Secrets must not be discoverable by reading the page source.
    it "hides undiscovered secret challenges" do
      sign_in user
      get season_path(season)

      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("challenges.defaults.s8_secret_early_bird.title")))
    end

    it "reveals a secret once it has been completed" do
      sign_in user
      participation = SeasonProgressService.ensure_participation(user, season)
      secret = season.season_challenges.secret.first
      participation.season_challenge_completions.create!(
        season_challenge: secret, xp_awarded: secret.xp_reward, completed_at: Time.current
      )

      get season_path(season)

      expect(response.body).to include(ERB::Util.html_escape(secret.challenge.display_title))
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
end
