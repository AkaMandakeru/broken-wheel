# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Appearance", type: :request do
  let(:user) { build_user }

  before { sign_in user }

  describe "GET /profile/appearance" do
    # Owned items render as an equip button carrying their key; locked ones have
    # no form at all. That difference is the assertion.
    def equippable?(key) = response.body.include?(%(value="#{key}"))

    it "defaults to banners, and only the owned one can be equipped" do
      grant_cosmetic(user, build_cosmetic(key: "legacy_of_champions", rarity: "legendary"))
      build_cosmetic(key: "summer_heat")

      get profile_appearance_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Legacy of champions", "Summer heat")
      expect(equippable?("legacy_of_champions")).to be(true)
      expect(equippable?("summer_heat")).to be(false)
    end

    it "switches to frames when asked" do
      grant_cosmetic(user, build_cosmetic(key: "champions_laurel", kind: "frame"))
      build_cosmetic(key: "a_banner", kind: "banner")

      get profile_appearance_path(kind: "frame")

      expect(response.body).to include("Champions laurel")
      expect(response.body).not_to include("A banner")
    end

    it "falls back to banners for a kind that is not pickable" do
      grant_cosmetic(user, build_cosmetic(key: "cold_start", kind: "banner"))
      build_cosmetic(key: "champions_laurel", kind: "frame")

      get profile_appearance_path(kind: "trail")

      expect(response.body).to include("Cold start")
      expect(response.body).not_to include("Champions laurel")
    end

    it "tells a locked item where it comes from" do
      locked = build_cosmetic(key: "topo_lines")
      season = build_season(name: "Season Nine")
      season.season_rewards.create!(reward_type: "cosmetic", reward_key: locked.key,
                                    unlock_kind: "level", level: 12, track: "free")

      get profile_appearance_path

      expect(response.body).to include("Season Nine")
    end
  end

  describe "PATCH /profile/appearance" do
    it "equips a cosmetic the user owns" do
      cosmetic = build_cosmetic(key: "cold_start")
      grant_cosmetic(user, cosmetic)

      patch profile_appearance_path, params: { kind: "banner", key: "cold_start" }

      expect(response).to redirect_to(profile_appearance_path(kind: "banner"))
      expect(user.reload.equipped["banner"]).to eq("cold_start")
    end

    it "refuses a cosmetic the user does not own" do
      build_cosmetic(key: "night_ride")

      patch profile_appearance_path, params: { kind: "banner", key: "night_ride" }

      expect(user.reload.equipped).to be_empty
      expect(flash[:alert]).to be_present
    end

    it "refuses an owned cosmetic that cannot be rendered yet" do
      cosmetic = build_cosmetic(key: "unfinished", renderable: false)
      grant_cosmetic(user, cosmetic)

      patch profile_appearance_path, params: { kind: "banner", key: "unfinished" }

      expect(user.reload.equipped).to be_empty
      expect(flash[:alert]).to be_present
    end

    it "unequips on a blank key without touching the other slot" do
      banner = build_cosmetic(key: "cold_start")
      frame = build_cosmetic(key: "steel_rim", kind: "frame")
      grant_cosmetic(user, banner)
      grant_cosmetic(user, frame)
      user.equip_cosmetic!("banner", "cold_start")
      user.equip_cosmetic!("frame", "steel_rim")

      patch profile_appearance_path, params: { kind: "banner", key: "" }

      expect(user.reload.equipped["banner"]).to be_nil
      expect(user.equipped["frame"]).to eq("steel_rim")
    end

    it "will not equip a banner into the frame slot" do
      banner = build_cosmetic(key: "cold_start", kind: "banner")
      grant_cosmetic(user, banner)

      patch profile_appearance_path, params: { kind: "frame", key: "cold_start" }

      expect(user.reload.equipped).to be_empty
    end
  end

  describe "the profile itself" do
    it "renders the equipped banner and frame" do
      banner = build_cosmetic(key: "legacy_of_champions", rarity: "legendary")
      frame = build_cosmetic(key: "champions_laurel", kind: "frame", rarity: "legendary")
      grant_cosmetic(user, banner)
      grant_cosmetic(user, frame)
      user.equip_cosmetic!("banner", banner.key)
      user.equip_cosmetic!("frame", frame.key)

      get profile_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Legacy of champions", "Champions laurel")
    end

    it "renders for a user wearing nothing" do
      get profile_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Default banner", "No frame yet")
    end
  end

  it "requires a signed-in user" do
    sign_out user

    get profile_appearance_path

    expect(response).to redirect_to(new_user_session_path)
  end
end
