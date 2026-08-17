# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Feature flags", type: :request do
  let(:user) { build_user }
  let(:admin) { build_user(admin: true) }

  def disable(key)
    FeatureFlag.set(key, false)
    Features.reset_cache
  end

  describe "defaults" do
    it "has everything on with an empty table" do
      expect(FeatureFlag.count).to eq(0)
      expect(Features.keys).to all(satisfy { |key| Features.enabled?(key) })
    end

    # A feature added to the catalogue later must work without a backfill.
    it "treats an unknown key as enabled" do
      expect(Features.enabled?(:something_new)).to be(true)
    end
  end

  describe "closing a feature's URLs" do
    before { sign_in user }

    # Hiding the nav link is not disabling a feature — a bookmark would still work.
    it "turns away a direct visit to a disabled feature" do
      disable(:clubs)

      get clubs_path

      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("features.unavailable", feature: "Clubs")))
    end

    it "still serves the feature while it is on" do
      get clubs_path

      expect(response).to have_http_status(:ok)
    end

    it "guards every controller the feature owns, not just the main one" do
      disable(:support)

      get support_tickets_path

      expect(response).to have_http_status(:redirect)
    end

    it "leaves other features alone" do
      disable(:clubs)

      get achievements_path

      expect(response).to have_http_status(:ok)
    end

    it "answers non-HTML requests with not found" do
      disable(:clubs)

      get clubs_path, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "redirect safety" do
    before { sign_in user }

    # Signed-in users land on the active season, which is also where a blocked
    # feature sends them — so disabling seasons must not bounce them in a loop.
    it "does not loop when the landing feature itself is disabled" do
      Seasons::BlueprintImporter.call("season_8_legacy_of_champions")
      disable(:seasons)

      get seasons_path
      expect(response).to have_http_status(:redirect)

      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "falls back to the root when seasons and challenges are both off" do
      disable(:seasons)
      disable(:challenges)

      get seasons_path
      follow_redirect!

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the navigation" do
    before { sign_in user }

    it "hides a disabled feature's links" do
      disable(:clubs)

      get profile_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(clubs_path)
    end

    it "shows them again once re-enabled" do
      disable(:clubs)
      FeatureFlag.set(:clubs, true)
      Features.reset_cache

      get profile_path

      expect(response.body).to include(clubs_path)
    end
  end

  describe "admin access" do
    before { sign_in admin }

    it "lists every feature with its state" do
      get admin_features_path

      expect(response).to have_http_status(:ok)
      Features.all.each { |feature| expect(response.body).to include(feature.name) }
    end

    it "switches a feature off and back on" do
      patch admin_feature_path("clubs"), params: { enabled: "false" }
      expect(Features.tap(&:reset_cache).enabled?(:clubs)).to be(false)

      patch admin_feature_path("clubs"), params: { enabled: "true" }
      expect(Features.tap(&:reset_cache).enabled?(:clubs)).to be(true)
    end

    it "records who switched it off" do
      patch admin_feature_path("clubs"), params: { enabled: "false" }

      flag = FeatureFlag.find_by(key: "clubs")
      expect(flag.disabled_by).to eq(admin.email)
      expect(flag.disabled_at).to be_present
    end

    it "rejects a key that is not in the catalogue" do
      patch admin_feature_path("not_a_feature"), params: { enabled: "false" }

      expect(response).to redirect_to(admin_features_path)
      expect(FeatureFlag.count).to eq(0)
    end

    # An admin who disabled the admin area could never switch it back on.
    it "does not offer admin or profile as switchable" do
      expect(Features.keys).not_to include("admin", "profiles", "profile")
    end

    it "keeps the admin area reachable with everything disabled" do
      Features.keys.each { |key| FeatureFlag.set(key, false) }
      Features.reset_cache

      get admin_features_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "authorisation" do
    it "keeps non-admins out of the toggles" do
      sign_in user

      patch admin_feature_path("clubs"), params: { enabled: "false" }

      expect(Features.tap(&:reset_cache).enabled?(:clubs)).to be(true)
    end
  end
end
