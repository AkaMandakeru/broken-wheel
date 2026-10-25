# frozen_string_literal: true

# Deletes what the mobile API leaves behind: replayable responses past their
# window, long-dead sessions and uploads that were never attached.
class ApiHousekeepingJob < ApplicationJob
  queue_as :default

  SESSION_RETENTION = 30.days
  UNATTACHED_BLOB_AGE = 2.days

  def perform
    IdempotencyKey.expired.in_batches.delete_all
    dead_sessions.in_batches.delete_all
    # An app that got an upload slot but never attached the image (closed,
    # crashed, gave up). purge_later deletes the file too.
    ActiveStorage::Blob.unattached.where(created_at: ...UNATTACHED_BLOB_AGE.ago).find_each(&:purge_later)
  end

  private

  # A revoked row is kept while its refresh token could still be presented, so
  # a stolen, already-rotated token still trips reuse detection (ApiSession.refresh!).
  def dead_sessions
    cutoff = SESSION_RETENTION.ago
    ApiSession.where(expires_at: ...cutoff)
              .or(ApiSession.where(revoked_at: ...cutoff, expires_at: ...Time.current))
  end
end
