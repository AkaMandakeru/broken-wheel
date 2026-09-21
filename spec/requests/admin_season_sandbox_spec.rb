# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::SeasonSandboxes", type: :request do
  let(:admin) { build_user(admin: true) }
  let(:player) { build_user }
  let(:season) { build_season(status: "upcoming") }

  around { |example| travel_to(Time.zone.local(2026, 7, 15, 12)) { example.run } }

  before { sign_in admin }

  context "when the sandbox is off" do
    it "does not exist" do
      get admin_season_sandbox_path(season)

      expect(response).to have_http_status(:not_found)
    end

    it "is not linked from the season page" do
      get admin_season_path(season)

      expect(response.body).not_to include(admin_season_sandbox_path(season))
    end
  end

  context "when the sandbox is on" do
    before { allow(SeasonSandbox).to receive(:enabled?).and_return(true) }

    it "is linked from the season page" do
      get admin_season_path(season)

      expect(response.body).to include(admin_season_sandbox_path(season))
    end

    it "finds a player by email" do
      get admin_season_sandbox_path(season, email: player.email.upcase)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(player.email)
      expect(response.body).to include(I18n.t("admin.season_sandbox.status.not_enrolled"))
    end

    it "renders a player's season once they are in it" do
      season.season_rewards.create!(level: 2, reward_type: "coins", reward_key: "coins", coins: 10)
      SeasonSandbox.new(season, player).set_level!(3)

      get admin_season_sandbox_path(season, user_id: player.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin.season_sandbox.rewards.granted"))
    end

    it "puts the player on a level" do
      post level_admin_season_sandbox_path(season, user_id: player.id), params: { level: 6 }

      expect(response).to redirect_to(admin_season_sandbox_path(season, user_id: player.id))
      expect(season.season_participations.find_by(user: player).level).to eq(6)
    end

    it "explains a request it cannot carry out" do
      post workouts_admin_season_sandbox_path(season, user_id: player.id), params: { count: 1, from: "2026-12-01", to: "2026-12-02" }

      expect(response).to redirect_to(admin_season_sandbox_path(season, user_id: player.id))
      expect(flash[:alert]).to be_present
    end

    it "resets the player" do
      SeasonSandbox.new(season, player).set_level!(4)

      delete reset_admin_season_sandbox_path(season, user_id: player.id)

      expect(season.season_participations.where(user: player)).to be_empty
    end

    it "stays closed to non-admins" do
      sign_in player

      get admin_season_sandbox_path(season)

      expect(response).to redirect_to(root_path)
    end
  end
end
