# frozen_string_literal: true

require "rails_helper"

RSpec.describe CosmeticStyle do
  def cosmetic(kind:, css_class: nil, rarity: "common")
    Cosmetic.new(key: "c", kind: kind, rarity: rarity, css_class: css_class)
  end

  it "turns a name colour class into one solid colour" do
    expect(described_class.render_data(cosmetic(kind: "name_color", css_class: "text-amber-500")))
      .to eq(type: "solid", colors: [ "#fe9a00" ])
  end

  # ring-4 is a width and ring-offset-* the gap around the ring: neither is the colour.
  it "takes a ring's colour, not its width or offset" do
    style = described_class.render_data(cosmetic(kind: "frame", css_class: "ring-4 ring-amber-300 ring-offset-2 ring-offset-green-900"))

    expect(style).to eq(type: "solid", colors: [ described_class::PALETTE["amber-300"] ])
  end

  it "keeps a gradient's stops in order" do
    style = described_class.render_data(cosmetic(kind: "banner", css_class: "bg-gradient-to-r from-slate-800 via-blue-900 to-slate-700"))

    expect(style).to eq(type: "gradient", colors: described_class::PALETTE.values_at("slate-800", "blue-900", "slate-700"))
  end

  it "falls back to the rarity's colours when the cosmetic has none of its own" do
    expect(described_class.render_data(cosmetic(kind: "banner", rarity: "rare")))
      .to eq(type: "gradient", colors: described_class::PALETTE.values_at("sky-400", "blue-500", "indigo-500"))
    expect(described_class.render_data(cosmetic(kind: "border", rarity: "epic", css_class: "text-not-a-colour")))
      .to eq(type: "solid", colors: [ described_class::PALETTE["purple-400"] ])
  end

  it "treats an unknown rarity as common" do
    expect(described_class.fallback_gradient("mythic")).to eq(described_class.fallback_gradient("common"))
  end

  it "only holds lowercase #rrggbb colours" do
    expect(described_class::PALETTE.values).to all(match(/\A#[0-9a-f]{6}\z/))
  end

  # A season blueprint that uses a colour missing from PALETTE would reach the
  # app as the rarity fallback instead of its own colour.
  it "knows every colour the season blueprints use" do
    classes = Rails.root.glob("db/seeds/seasons/*.yml").flat_map do |file|
      Array(YAML.safe_load_file(file, aliases: true, permitted_classes: [ Date, Time ])["cosmetics"]).filter_map { |entry| entry["css_class"] }
    end
    expect(classes).not_to be_empty

    tokens = classes.flat_map(&:split).filter_map { |token| token[/\A(?:from|via|to|text|ring|border|bg)-(?!offset-)(.+)\z/, 1] }
    colours = tokens.grep(/\A[a-z]+-\d{2,3}\z/)

    expect(colours - described_class::PALETTE.keys).to be_empty
    classes.each { |css_class| expect(described_class.from_classes(css_class)).to be_present, css_class }
  end

  it "is what the web helper draws with, so the page and the app agree" do
    helper = Class.new { include CosmeticsHelper }.new

    Cosmetic::RARITIES.each do |rarity|
      expect(helper.cosmetic_fallback_gradient(Cosmetic.new(rarity: rarity))).to eq(described_class.fallback_gradient(rarity))
      expect(helper.cosmetic_rarity_border(rarity)).to eq(described_class.rarity_border(rarity))
    end
  end
end
