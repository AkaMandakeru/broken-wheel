# frozen_string_literal: true

# Loaded on demand by Active Storage only when storage.yml uses it.
require "active_storage/service/mirror_service"

module Storage
  # Copies every existing blob to the mirrors of the configured `mirror`
  # service (docs/MOBILE_API_PLAN.md §5), so a new bucket can take over without
  # losing files. New uploads are already written to both by MirrorService.
  #
  # A continuation: the cursor is the last blob id done, so a deploy or dyno
  # restart resumes there instead of starting over. MirrorService#mirror skips
  # keys a mirror already has, so re-running it is cheap.
  class MirrorBlobsJob < ApplicationJob
    include ActiveJob::Continuable

    queue_as :default

    def perform
      service = ActiveStorage::Blob.service
      unless service.is_a?(ActiveStorage::Service::MirrorService)
        Rails.logger.info("Storage::MirrorBlobsJob: the Active Storage service is not a mirror; nothing to copy")
        return
      end

      step :mirror do |step|
        # Blobs from before the switch name the primary service, newer ones the mirror.
        blobs = ActiveStorage::Blob.where(service_name: [ service.name, service.primary.name ].compact.map(&:to_s))
        blobs.find_each(start: step.cursor) do |blob|
          mirror(service, blob)
          step.advance! from: blob.id
        end
      end
    end

    private

    def mirror(service, blob)
      service.mirror(blob.key, checksum: blob.checksum)
    rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError => e
      Rails.logger.warn("Storage::MirrorBlobsJob: skipped blob=#{blob.id} (#{e.class})")
    end
  end
end
