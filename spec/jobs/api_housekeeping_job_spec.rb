# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiHousekeepingJob do
  include ActiveJob::TestHelper

  let(:user) { build_user }

  def session(**attributes)
    ApiSession.start!(user).session.tap { it.update_columns(attributes) if attributes.any? }
  end

  it "deletes Idempotency-Key responses past their window" do
    old = IdempotencyKey.create!(user: user, key: "old", request_digest: "d", created_at: 25.hours.ago)
    fresh = IdempotencyKey.create!(user: user, key: "fresh", request_digest: "d")

    described_class.perform_now

    expect(IdempotencyKey.ids).to eq([ fresh.id ])
    expect(IdempotencyKey.exists?(old.id)).to be(false)
  end

  it "deletes sessions that died more than 30 days ago, but keeps rotated ones whose token could still come back" do
    active = session
    long_expired = session(expires_at: 31.days.ago)
    recently_expired = session(expires_at: 1.day.ago)
    revoked_and_expired = session(revoked_at: 40.days.ago, revoked_reason: "rotated", expires_at: 1.day.ago)
    revoked_still_valid = session(revoked_at: 40.days.ago, revoked_reason: "rotated", expires_at: 20.days.from_now)
    recently_revoked = session(revoked_at: 1.day.ago, revoked_reason: "logout")

    described_class.perform_now

    expect(ApiSession.ids).to contain_exactly(active.id, recently_expired.id, revoked_still_valid.id, recently_revoked.id)
    expect(ApiSession.exists?(long_expired.id)).to be(false)
    expect(ApiSession.exists?(revoked_and_expired.id)).to be(false)
  end

  it "purges uploads that were never attached after two days" do
    abandoned = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("a"), filename: "a.png")
    abandoned.update_columns(created_at: 3.days.ago)
    in_flight = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("b"), filename: "b.png")
    attached = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("c"), filename: "c.png")
    attached.update_columns(created_at: 3.days.ago)
    user.avatar.attach(attached)

    perform_enqueued_jobs(only: ActiveStorage::PurgeJob) { described_class.perform_now }

    expect(ActiveStorage::Blob.exists?(abandoned.id)).to be(false)
    expect(ActiveStorage::Blob.exists?(in_flight.id)).to be(true)
    expect(ActiveStorage::Blob.exists?(attached.id)).to be(true)
  end
end
