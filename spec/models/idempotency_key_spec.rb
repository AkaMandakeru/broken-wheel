# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdempotencyKey do
  let(:user) { build_user }

  it "hands the first request a fresh record and replays it afterwards" do
    first = described_class.claim(user: user, key: "k1", request_digest: "a")
    expect(first).to be_previously_new_record

    expect(described_class.claim(user: user, key: "k1", request_digest: "a")).to be_a(IdempotencyKey::InProgress)

    first.finish(status: 201, body: { data: { id: 1 } }.to_json)
    replay = described_class.claim(user: user, key: "k1", request_digest: "a")
    expect(replay).to have_attributes(response_status: 201, response_body: { "data" => { "id" => 1 } })
  end

  it "refuses the same key for a different request" do
    described_class.claim(user: user, key: "k1", request_digest: "a").finish(status: 201, body: "")

    expect(described_class.claim(user: user, key: "k1", request_digest: "b")).to be_a(IdempotencyKey::Conflict)
  end

  it "forgets server errors so the client can retry" do
    described_class.claim(user: user, key: "k1", request_digest: "a").finish(status: 500, body: "")

    expect(described_class.claim(user: user, key: "k1", request_digest: "a")).to be_previously_new_record
  end

  it "keys are per user and expire" do
    described_class.claim(user: user, key: "k1", request_digest: "a").finish(status: 201, body: "")

    expect(described_class.claim(user: build_user, key: "k1", request_digest: "b")).to be_previously_new_record
    travel IdempotencyKey::TTL + 1.minute do
      expect(described_class.claim(user: user, key: "k1", request_digest: "b")).to be_previously_new_record
    end
  end
end
