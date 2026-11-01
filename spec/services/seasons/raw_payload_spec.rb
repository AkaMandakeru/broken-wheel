# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seasons::RawPayload do
  describe ".field" do
    # The sync job reads SummaryActivity, which doesn't declare `calories`.
    let(:summary) { Strava::Models::SummaryActivity.new("id" => 1, "moving_time" => 1800, "map" => { "summary_polyline" => "abc" }) }

    it "reads a Strava model's declared fields" do
      expect(described_class.field(summary, :moving_time)).to eq(1800)
    end

    it "returns nil for a field the Strava model doesn't declare or Strava didn't send" do
      expect(described_class.field(summary, :calories)).to be_nil
      expect(described_class.field(summary, :total_elevation_gain)).to be_nil
    end

    it "reads a model's `map` field, not Enumerable#map" do
      expect(described_class.route_signature(summary)).to be_present
    end

    it "reads replayed payload hashes with string or symbol keys" do
      expect(described_class.field({ "calories" => 300 }, :calories)).to eq(300)
      expect(described_class.field({ calories: 300 }, :calories)).to eq(300)
      expect(described_class.field({ "map" => { "summary_polyline" => "abc" } }, :map)).to eq("summary_polyline" => "abc")
    end
  end
end
