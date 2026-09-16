# frozen_string_literal: true

require "rails_helper"

# Spec types are not inferred from location in this suite (see rails_helper),
# so the type is declared.
RSpec.describe CosmeticsHelper, type: :helper do
  describe "#cosmetic_image_source" do
    it "is nil when there is no cosmetic at all" do
      expect(helper.cosmetic_image_source(nil, resize: [ 100, 100 ])).to be_nil
    end

    it "is nil when the cosmetic has no picture yet" do
      cosmetic = build_cosmetic(key: "pending_art")

      expect(helper.cosmetic_image_source(cosmetic, resize: [ 100, 100 ])).to be_nil
    end

    it "crops banners to fill the slot" do
      cosmetic = attach_cosmetic_art(build_cosmetic(key: "banner_art"))

      variant = helper.cosmetic_image_source(cosmetic, resize: [ 1200, 400 ])

      expect(variant.variation.transformations).to include(resize_to_fill: [ 1200, 400 ])
    end

    # Frames are transparent rings. resize_to_fill would crop the ornament off,
    # so anything non-cropping has to go through resize_to_limit.
    it "fits frames inside the box instead of cropping them" do
      cosmetic = attach_cosmetic_art(build_cosmetic(key: "frame_art", kind: "frame"))

      variant = helper.cosmetic_image_source(cosmetic, resize: [ 192, 192 ], crop: false)

      expect(variant.variation.transformations).to include(resize_to_limit: [ 192, 192 ])
      expect(variant.variation.transformations).not_to have_key(:resize_to_fill)
    end

    # A blob that cannot be transformed would otherwise raise while the profile
    # is rendering and take the whole page down with it.
    it "degrades to nil when the blob cannot be transformed" do
      cosmetic = attach_cosmetic_art(build_cosmetic(key: "broken_art"))
      allow(cosmetic.image).to receive(:variable?).and_raise(ActiveStorage::Error)

      expect(helper.cosmetic_image_source(cosmetic, resize: [ 100, 100 ])).to be_nil
    end

    it "degrades to nil when the file has gone missing" do
      cosmetic = attach_cosmetic_art(build_cosmetic(key: "missing_art"))
      allow(cosmetic.image).to receive(:variable?).and_raise(ActiveStorage::FileNotFoundError)

      expect(helper.cosmetic_image_source(cosmetic, resize: [ 100, 100 ])).to be_nil
    end

    it "serves the original when the file is not variable" do
      cosmetic = attach_cosmetic_art(build_cosmetic(key: "not_variable"))
      allow(cosmetic.image).to receive(:variable?).and_return(false)

      expect(helper.cosmetic_image_source(cosmetic, resize: [ 100, 100 ])).to eq(cosmetic.image)
    end
  end

  describe "#cosmetic_fallback_gradient" do
    it "gives each rarity its own gradient" do
      gradients = Cosmetic::RARITIES.map do |rarity|
        helper.cosmetic_fallback_gradient(build_cosmetic(key: "grad_#{rarity}", rarity: rarity))
      end

      expect(gradients.uniq.size).to eq(Cosmetic::RARITIES.size)
    end

    it "falls back to the brand gradient when nothing is equipped" do
      expect(helper.cosmetic_fallback_gradient(nil)).to include("from-primary")
    end
  end

  describe "#cosmetic_rarity_chip" do
    it "is nil for an empty slot, so nothing renders as a blank pill" do
      expect(helper.cosmetic_rarity_chip(nil)).to be_nil
    end

    it "carries the rarity label and its colour" do
      chip = helper.cosmetic_rarity_chip(build_cosmetic(key: "chip", rarity: "legendary"))

      expect(chip).to include("Legendary")
      expect(chip).to include(helper.cosmetic_rarity_classes("legendary"))
    end
  end

  describe "#cosmetic_rarity_border" do
    it "gives each rarity its own ring colour" do
      borders = Cosmetic::RARITIES.map { |rarity| helper.cosmetic_rarity_border(rarity) }

      expect(borders.uniq.size).to eq(Cosmetic::RARITIES.size)
    end

    it "falls back to grey for anything unrecognised" do
      expect(helper.cosmetic_rarity_border(nil)).to eq("border-gray-300")
    end
  end
end
