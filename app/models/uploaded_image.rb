# frozen_string_literal: true

# The rules for images players upload from the app, at both ends of a direct
# upload: checked before a slot is handed out, and again when the app attaches
# the blob — because the app can claim anything at step one.
#
#   UploadedImage.prepare!(user:, purpose: "avatar", filename:, content_type:, byte_size:, checksum:)
#   user.avatar.attach(UploadedImage.find!(signed_id, user: user, purpose: "avatar"))
module UploadedImage
  PURPOSES = %w[avatar timeline_post].freeze
  CONTENT_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  MAX_BYTES = 5.megabytes

  class Invalid < StandardError
    attr_reader :attribute

    def initialize(attribute, message)
      @attribute = attribute
      super(message)
    end
  end

  module_function

  def prepare!(user:, purpose:, filename:, content_type:, byte_size:, checksum:)
    validate!(purpose: purpose, content_type: content_type, byte_size: byte_size.to_i)
    raise Invalid.new(:checksum, I18n.t("api.uploads.checksum_missing")) if checksum.blank?

    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: filename.to_s.presence || "upload", byte_size: byte_size.to_i, checksum: checksum,
      content_type: content_type, metadata: { "uploader_id" => user.id, "purpose" => purpose }
    )

    {
      signed_id: blob.signed_id,
      direct_upload: { url: blob.service_url_for_direct_upload, headers: blob.service_headers_for_direct_upload }
    }
  end

  # The blob behind a signed id, if this user uploaded it for this purpose and
  # the bytes actually arrived. Raises Invalid otherwise.
  def find!(signed_id, user:, purpose:)
    blob = ActiveStorage::Blob.find_signed(signed_id.to_s)
    raise Invalid.new(purpose, I18n.t("api.uploads.unknown")) unless blob
    raise Invalid.new(purpose, I18n.t("api.uploads.unknown")) unless blob.metadata["uploader_id"] == user.id && blob.metadata["purpose"] == purpose

    validate!(purpose: purpose, content_type: blob.content_type, byte_size: blob.byte_size)
    raise Invalid.new(purpose, I18n.t("api.uploads.not_uploaded")) unless blob.service.exist?(blob.key)

    blob
  end

  def validate!(purpose:, content_type:, byte_size:)
    raise Invalid.new(:purpose, I18n.t("api.uploads.bad_purpose")) unless PURPOSES.include?(purpose)
    raise Invalid.new(:content_type, I18n.t("api.uploads.bad_type")) unless CONTENT_TYPES.include?(content_type)
    raise Invalid.new(:byte_size, I18n.t("api.uploads.too_large", size: "#{MAX_BYTES / 1.megabyte} MB")) unless byte_size.positive? && byte_size <= MAX_BYTES
  end
end
