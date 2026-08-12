# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Seasons", type: :request do
  let(:admin) { build_user(admin: true) }
  let!(:season) { Seasons::BlueprintImporter.call("season_8_legacy_of_champions") }

  before { sign_in admin }

  it "renders the season admin page with the new battle pass fields" do
    # The attach form only renders when a challenge is still unattached.
    build_challenge(key: "unattached_one", requirements: [ { metric: "distance_km", target: 5 } ])

    get admin_season_path(season)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.seasons.challenges.category"))
    expect(response.body).to include(I18n.t("admin.seasons.challenges.unlock_level"))
    expect(response.body).to include(I18n.t("admin.seasons.rewards.track"))
  end

  it "renders the season form with slogan, max level and time zone" do
    get edit_admin_season_path(season)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.seasons.fields.slogan"))
    expect(response.body).to include(I18n.t("admin.seasons.fields.max_level"))
    expect(response.body).to include(I18n.t("admin.seasons.fields.time_zone"))
  end

  # A `step` the stored value does not land on makes the browser reject the form
  # on every save, without the operator touching the field. 17110 is not a
  # multiple of 100 from a min of 1.
  it "does not constrain numeric fields to a step their own value would fail" do
    season.update!(top_level_xp: 17_110, xp_multiplier: 1.25)

    get edit_admin_season_path(season)

    %w[top_level_xp curve_exponent xp_multiplier].each do |field|
      tag = response.body[/<input[^>]*name="season\[#{field}\]"[^>]*>/]
      expect(tag).to be_present, "no input rendered for #{field}"

      step = tag[/step="([^"]*)"/, 1]
      expect([ nil, "any", "1" ]).to include(step),
                                     "#{field} has step=#{step.inspect}, which can reject its own stored value"
    end
  end

  describe "saving an untouched form" do
    it "accepts the season's own current values" do
      patch admin_season_path(season), params: { season: {
        name: season.name, max_level: season.max_level,
        top_level_xp: season.top_level_xp, curve_exponent: season.curve_exponent,
        xp_multiplier: season.xp_multiplier, status: season.status, theme: season.theme
      } }

      expect(response).to redirect_to(admin_season_path(season))
      expect(season.reload.errors).to be_empty
    end

    # Blank casts to nil, and the column is NOT NULL with a sensible default, so
    # a cleared field should mean "use the default" rather than fail validation.
    it "falls back to the default when the curve exponent is cleared" do
      patch admin_season_path(season), params: { season: { name: season.name, curve_exponent: "" } }

      expect(response).to redirect_to(admin_season_path(season))
      expect(season.reload.curve_exponent.to_f).to eq(Seasons::LevelCurve::DEFAULT_EXPONENT)
    end

    it "falls back to the default top level XP when cleared" do
      patch admin_season_path(season), params: { season: { name: season.name, top_level_xp: "" } }

      expect(response).to redirect_to(admin_season_path(season))
      expect(season.reload.effective_top_level_xp).to eq(Seasons::LevelCurve::DEFAULT_TOP_LEVEL_XP)
    end
  end

  it "attaches a challenge with category and unlock level" do
    challenge = build_challenge(key: "extra_one", requirements: [ { metric: "distance_km", target: 5 } ])

    post admin_season_season_challenges_path(season), params: {
      season_challenge: {
        challenge_id: challenge.id, xp_reward: 500, category: "elite",
        unlock_level: 20, coin_reward: 100, fragment_reward: 5, hidden: "0"
      }
    }

    attached = season.season_challenges.find_by(challenge: challenge)
    expect(attached.category).to eq("elite")
    expect(attached.unlock_level).to eq(20)
    expect(attached.coin_reward).to eq(100)
  end

  it "creates a premium-track reward" do
    post admin_season_season_rewards_path(season), params: {
      season_reward: {
        level: 7, reward_type: "coins", reward_key: "admin_coins", name: "Admin Coins",
        track: "premium", coins: 250
      }
    }

    reward = season.season_rewards.find_by(reward_key: "admin_coins")
    expect(reward.track).to eq("premium")
    expect(reward.coins).to eq(250)
    expect(reward.unlock_value).to eq(7)
  end
end
