# frozen_string_literal: true

# The stored first response to a POST sent with an Idempotency-Key. See
# Api::Idempotent.
class IdempotencyKey < ApplicationRecord
  TTL = 24.hours

  # The same key sent with a different request.
  Conflict = Data.define
  # The first request with this key has not finished yet.
  InProgress = Data.define

  belongs_to :user

  scope :expired, -> { where(created_at: ...TTL.ago) }

  # The record to replay, a fresh record to fill in, or Conflict / InProgress.
  # The unique index on (user_id, key) decides which of two racing requests
  # gets to run.
  def self.claim(user:, key:, request_digest:)
    expired.where(user: user, key: key).delete_all
    record = create_or_find_by!(user: user, key: key) { |row| row.request_digest = request_digest }

    return record if record.previously_new_record?
    return Conflict.new if record.request_digest != request_digest
    return InProgress.new unless record.completed?

    record
  end

  def completed? = response_status.present?

  # Server errors are not stored, so the client can retry them.
  def finish(status:, body:)
    return destroy if status >= 500

    update!(response_status: status, response_body: body.present? ? JSON.parse(body) : nil)
  end
end
