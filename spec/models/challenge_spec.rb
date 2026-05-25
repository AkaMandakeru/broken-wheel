# frozen_string_literal: true

require "rails_helper"

RSpec.describe Challenge, type: :model do
  describe ".current_week_window" do
    it "returns a Sunday-to-Saturday range relative to a given day" do
      wednesday = Date.new(2026, 5, 6)
      window = described_class.current_week_window(today: wednesday)

      expect(window.begin).to eq(Date.new(2026, 5, 3))
      expect(window.begin.wday).to eq(0)
      expect(window.end).to eq(Date.new(2026, 5, 9))
      expect(window.end.wday).to eq(6)
    end

    it "uses Date.current when no day is provided" do
      window = described_class.current_week_window

      expect(window.begin).to eq(Date.current.beginning_of_week(:sunday))
      expect(window.end).to eq(Date.current.end_of_week(:sunday))
    end

    it "starts a new week on Sunday" do
      sunday = Date.new(2026, 5, 10)
      window = described_class.current_week_window(today: sunday)

      expect(window.begin).to eq(sunday)
      expect(window.begin.wday).to eq(0)
      expect(window.end).to eq(Date.new(2026, 5, 16))
      expect(window.end.wday).to eq(6)
    end

    it "ends the week on Saturday" do
      saturday = Date.new(2026, 5, 9)
      window = described_class.current_week_window(today: saturday)

      expect(window.begin).to eq(Date.new(2026, 5, 3))
      expect(window.end).to eq(saturday)
    end
  end
end
