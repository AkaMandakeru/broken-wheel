# frozen_string_literal: true

require "rails_helper"

# Behaviour every endpoint inherits from Api::V1::BaseController's concerns,
# exercised through real endpoints.
RSpec.describe "API v1 foundation", type: :request do
  let(:user) { build_user }

  it "answers 400 for a cursor it can't decode, even on an empty list" do
    get "/api/v1/workouts", params: { cursor: "not-a-cursor" }, headers: api_headers(user)

    expect(response).to have_http_status(:bad_request)
    expect(json_error_code).to eq("invalid_cursor")
  end

  it "releases an idempotency key when the action fails, so the retry runs" do
    headers = api_headers(user, "Idempotency-Key" => "abc")
    body = { workout: { sport: "run", workout_date: "2026-08-10", distance_km: 5, duration_seconds: 1800 } }
    allow(Workouts::ManualEntry).to receive(:new).and_raise(ActiveRecord::RecordNotFound)

    post "/api/v1/workouts", params: body, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(IdempotencyKey.where(user: user, key: "abc")).not_to exist

    allow(Workouts::ManualEntry).to receive(:new).and_call_original
    post "/api/v1/workouts", params: body, headers: headers, as: :json
    expect(response).to have_http_status(:created)
  end

  it "pages through rows created in the same millisecond without skipping any" do
    user.update!(first_name: "Me")
    others = Array.new(5) { build_user }
    stamp = Time.zone.parse("2026-08-10 12:00:00.123456")
    others.each_with_index do |other, index|
      UserBlock.create!(blocker: user, blocked: other, created_at: stamp + (index * 0.0001).seconds)
    end

    seen = []
    cursor = nil
    loop do
      get "/api/v1/blocks", params: { limit: 2, cursor: cursor }.compact, headers: api_headers(user)
      seen.concat(json_data.map { |block| block.dig("user", "id") || block["id"] })
      cursor = json_body.dig("meta", "next_cursor")
      break if cursor.nil?
    end

    expect(seen.size).to eq(5)
  end
end
