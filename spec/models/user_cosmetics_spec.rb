# frozen_string_literal: true

require "rails_helper"

# What a player owns and what they are wearing. equipped_cosmetics is a jsonb
# map of kind => key, so every read here has to survive the key pointing at
# something the user no longer owns.
RSpec.describe User, type: :model do
  let(:user) { build_user }
  let!(:banner) { build_cosmetic(key: "legacy_of_champions", kind: "banner", rarity: "legendary") }
  let!(:frame)  { build_cosmetic(key: "champions_laurel", kind: "frame", rarity: "legendary") }

  describe "#equip_cosmetic!" do
    it "equips something the user owns" do
      grant_cosmetic(user, banner)

      expect(user.equip_cosmetic!("banner", "legacy_of_champions")).to be(true)
      expect(user.reload.equipped["banner"]).to eq("legacy_of_champions")
    end

    it "refuses something the user does not own" do
      expect(user.equip_cosmetic!("banner", "legacy_of_champions")).to be(false)
      expect(user.reload.equipped).to be_empty
    end

    it "refuses an owned cosmetic whose art has not landed yet" do
      pending_art = build_cosmetic(key: "unfinished", kind: "banner", renderable: false)
      grant_cosmetic(user, pending_art)

      expect(user.equip_cosmetic!("banner", "unfinished")).to be(false)
      expect(user.reload.equipped).to be_empty
    end

    # The kind is part of the lookup, not just the slot name — otherwise a
    # banner could be equipped into the frame slot and render as a ring.
    it "refuses to put a banner in the frame slot" do
      grant_cosmetic(user, banner)

      expect(user.equip_cosmetic!("frame", "legacy_of_champions")).to be(false)
      expect(user.reload.equipped).to be_empty
    end

    it "replaces whatever was in that slot" do
      other = build_cosmetic(key: "cold_start", kind: "banner")
      grant_cosmetic(user, banner)
      grant_cosmetic(user, other)
      user.equip_cosmetic!("banner", "legacy_of_champions")

      user.equip_cosmetic!("banner", "cold_start")

      expect(user.reload.equipped["banner"]).to eq("cold_start")
    end
  end

  describe "#unequip_cosmetic!" do
    it "clears one slot and leaves the other alone" do
      grant_cosmetic(user, banner)
      grant_cosmetic(user, frame)
      user.equip_cosmetic!("banner", banner.key)
      user.equip_cosmetic!("frame", frame.key)

      user.unequip_cosmetic!("banner")

      expect(user.reload.equipped["banner"]).to be_nil
      expect(user.equipped["frame"]).to eq("champions_laurel")
    end

    it "is harmless on an empty slot" do
      expect { user.unequip_cosmetic!("banner") }.not_to raise_error
    end
  end

  describe "#equipped_cosmetic" do
    it "returns nil for an empty slot" do
      expect(user.equipped_cosmetic("banner")).to be_nil
    end

    it "returns the record for a filled one" do
      grant_cosmetic(user, banner)
      user.equip_cosmetic!("banner", banner.key)

      expect(user.reload.equipped_cosmetic("banner")).to eq(banner)
    end

    # The lookup goes through ownership, so a key left behind by an admin
    # deleting the row — or by ownership being revoked — reads as "nothing
    # equipped" rather than blowing up the profile.
    it "returns nil when the key survives but the ownership does not" do
      grant_cosmetic(user, banner)
      user.equip_cosmetic!("banner", banner.key)
      user.user_cosmetics.destroy_all

      expect(user.reload.equipped["banner"]).to eq("legacy_of_champions")
      expect(user.equipped_cosmetic("banner")).to be_nil
    end

    it "reads each slot through its own accessor" do
      grant_cosmetic(user, banner)
      grant_cosmetic(user, frame)
      user.equip_cosmetic!("banner", banner.key)
      user.equip_cosmetic!("frame", frame.key)
      user.reload

      expect(user.equipped_banner).to eq(banner)
      expect(user.equipped_frame).to eq(frame)
    end
  end

  describe "#owned_cosmetics and #unowned_cosmetics" do
    let!(:second_banner) { build_cosmetic(key: "cold_start", kind: "banner", position: 1) }
    let!(:unrenderable) { build_cosmetic(key: "unfinished", kind: "banner", renderable: false) }

    before { grant_cosmetic(user, banner) }

    it "returns only the asked-for kind" do
      grant_cosmetic(user, frame)

      expect(user.owned_cosmetics("banner")).to contain_exactly(banner)
      expect(user.owned_cosmetics("frame")).to contain_exactly(frame)
    end

    it "leaves out anything that cannot be equipped" do
      grant_cosmetic(user, unrenderable)

      expect(user.owned_cosmetics("banner")).to contain_exactly(banner)
    end

    it "returns the rest of the catalogue as unowned" do
      expect(user.unowned_cosmetics("banner")).to contain_exactly(second_banner)
    end

    it "counts nothing as unowned once it is granted" do
      grant_cosmetic(user, second_banner)

      expect(user.unowned_cosmetics("banner")).to be_empty
    end

    it "never lists the same cosmetic as both owned and unowned" do
      owned = user.owned_cosmetics("banner").to_a
      unowned = user.unowned_cosmetics("banner").to_a

      expect(owned & unowned).to be_empty
    end
  end

  describe "#owns_cosmetic?" do
    it "tracks the grant" do
      expect(user.owns_cosmetic?("legacy_of_champions")).to be(false)

      grant_cosmetic(user, banner)

      expect(user.reload.owns_cosmetic?("legacy_of_champions")).to be(true)
    end
  end
end
