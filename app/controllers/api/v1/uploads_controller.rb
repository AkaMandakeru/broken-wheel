# frozen_string_literal: true

module Api
  module V1
    # Step one of an image upload: a direct-upload slot. The app PUTs the bytes
    # straight to storage, then attaches the blob by `signed_id` (for example
    # `PATCH /api/v1/me { avatar: signed_id }`). Rails never handles the bytes.
    class UploadsController < BaseController
      rate_limit to: 30, within: 1.hour, only: :create, by: -> { current_user.id }

      def create
        slot = UploadedImage.prepare!(user: current_user, **upload_params.to_h.symbolize_keys)
        render_data(slot, status: :created)
      rescue UploadedImage::Invalid => error
        render_error :unprocessable_content, "invalid_upload", fields: { error.attribute => [ error.message ] }
      end

      private

      def upload_params
        params.expect(upload: [ :purpose, :filename, :content_type, :byte_size, :checksum ])
      end
    end
  end
end
