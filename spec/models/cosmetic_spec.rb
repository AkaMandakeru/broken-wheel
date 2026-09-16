# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cosmetic, type: :model do
  describe "validations" do
    it "requires a key" do
      cosmetic = described_class.new(kind: "banner", rarity: "common")

      expect(cosmetic).not_to be_valid
      expect(cosmetic.errors[:key]).to be_present
    end

    it "requires the key to be unique" do
      build_cosmetic(key: "taken")
      duplicate = described_class.new(key: "taken", kind: "banner", rarity: "common")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).to be_present
    end

    it "rejects a kind outside the catalogue" do
      cosmetic = described_class.new(key: "odd", kind: "spaceship", rarity: "common")

      expect(cosmetic).not_to be_valid
      expect(cosmetic.errors[:kind]).to be_present
    end

    it "rejects a rarity outside the ladder" do
      cosmetic = described_class.new(key: "odd", kind: "banner", rarity: "mythic")

      expect(cosmetic).not_to be_valid
      expect(cosmetic.errors[:rarity]).to be_present
    end

    it "defaults to common and renderable" do
      cosmetic = build_cosmetic(key: "plain", rarity: "common")

      expect(cosmetic.rarity).to eq("common")
      expect(cosmetic).to be_renderable
      expect(cosmetic.position).to eq(0)
    end
  end

  describe "artwork" do
    it "accepts a supported picture" do
      cosmetic = attach_cosmetic_art(build_cosmetic(key: "with_art"))

      expect(cosmetic).to be_valid
      expect(cosmetic.image).to be_attached
    end

    it "rejects a file that is not an image" do
      cosmetic = build_cosmetic(key: "bad_upload")
      attach_cosmetic_art(cosmetic, file: "not_an_image.txt", content_type: "text/plain")

      expect(cosmetic).not_to be_valid
      expect(cosmetic.errors[:image].join).to match(/image|PNG/i)
    end

    it "rejects a picture over the size limit" do
      cosmetic = attach_cosmetic_art(build_cosmetic(key: "too_big"))
      allow(cosmetic.image.blob).to receive(:byte_size).and_return(described_class::MAX_IMAGE_BYTES + 1)

      expect(cosmetic).not_to be_valid
      expect(cosmetic.errors[:image]).to be_present
    end

    # Seasons::BlueprintImporter creates cosmetics straight from YAML, long
    # before anyone draws them. If the image were required, importing a season
    # would fail — so a picture kind with no picture has to stay valid.
    it "stays valid with no picture at all" do
      expect(build_cosmetic(key: "pending_art", kind: "frame")).to be_valid
    end

    describe "#picture?" do
      it "is true for the kinds whose art is an upload" do
        expect(build_cosmetic(key: "b", kind: "banner")).to be_picture
        expect(build_cosmetic(key: "f", kind: "frame")).to be_picture
      end

      it "is false for a CSS-class kind" do
        expect(build_cosmetic(key: "t", kind: "trail")).not_to be_picture
      end
    end

    describe "#artwork?" do
      it "is false until a picture is attached" do
        expect(build_cosmetic(key: "empty", kind: "banner").artwork?).to be(false)
      end

      it "is true once one is" do
        expect(attach_cosmetic_art(build_cosmetic(key: "full", kind: "banner")).artwork?).to be(true)
      end

      it "is false for a kind that does not render from a picture" do
        cosmetic = attach_cosmetic_art(build_cosmetic(key: "trail_art", kind: "trail"))

        expect(cosmetic.artwork?).to be(false)
      end
    end
  end

  describe "display text" do
    it "prefers a translation when one exists" do
      cosmetic = build_cosmetic(key: "translated", name: "Database Name")

      I18n.backend.store_translations(:en, cosmetics: { items: { translated: "Translated Name" } })

      expect(cosmetic.display_name).to eq("Translated Name")
    ensure
      I18n.backend.reload!
    end

    it "falls back to the stored name" do
      expect(build_cosmetic(key: "no_translation", name: "Stored Name").display_name).to eq("Stored Name")
    end

    it "falls back to a humanised key when there is no name either" do
      expect(build_cosmetic(key: "legacy_of_champions", name: nil).display_name).to eq("Legacy of champions")
    end

    it "labels the rarity" do
      expect(build_cosmetic(key: "r", rarity: "legendary").rarity_label).to eq("Legendary")
    end
  end

  describe "scopes" do
    let!(:banner) { build_cosmetic(key: "a_banner", kind: "banner", position: 2) }
    let!(:frame)  { build_cosmetic(key: "a_frame", kind: "frame") }
    let!(:hidden) { build_cosmetic(key: "hidden", kind: "banner", renderable: false, position: 1) }

    it "filters by kind" do
      expect(described_class.banners).to contain_exactly(banner, hidden)
      expect(described_class.frames).to contain_exactly(frame)
      expect(described_class.of_kind("frame")).to contain_exactly(frame)
    end

    it "filters out what cannot be equipped" do
      expect(described_class.renderable).to contain_exactly(banner, frame)
    end

    it "orders by position, then key, so the sequence never depends on insertion order" do
      expect(described_class.banners.ordered).to eq([ hidden, banner ])
    end

    it "accepts several kinds at once, which is how the admin groups them" do
      expect(described_class.of_kind(described_class::PICTURE_KINDS)).to contain_exactly(banner, frame, hidden)
    end
  end
end
