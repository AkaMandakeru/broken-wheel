# frozen_string_literal: true

require "rails_helper"

RSpec.describe Challenge, type: :model do
  describe ".current_week_window" do
    it "returns a Monday-to-Sunday range relative to a given day" do
      wednesday = Date.new(2026, 5, 6)
      window = described_class.current_week_window(today: wednesday)

      expect(window.begin).to eq(Date.new(2026, 5, 4))
      expect(window.end).to eq(Date.new(2026, 5, 10))
    end

    it "uses Date.current when no day is provided" do
      window = described_class.current_week_window

      expect(window.begin).to eq(Date.current.beginning_of_week(:monday))
      expect(window.end).to eq(Date.current.end_of_week(:monday))
    end

    it "anchors to Monday even when today is a Sunday" do
      sunday = Date.new(2026, 5, 10)
      window = described_class.current_week_window(today: sunday)

      expect(window.begin.wday).to eq(1)
      expect(window.end).to eq(sunday)
    end
  end
end
