# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 uploads", type: :request do
  let(:user) { build_user }
  let(:bytes) { file_fixture("season_cover.png").binread }
  let(:checksum) { OpenSSL::Digest::MD5.base64digest(bytes) }

  path "/api/v1/uploads" do
    post "Get a direct-upload slot for an image" do
      tags "Uploads"
      description "PUT the bytes to `direct_upload.url` with `direct_upload.headers`, then attach the image by `signed_id`."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: [ "upload" ],
        properties: {
          upload: {
            type: :object,
            required: %w[purpose filename content_type byte_size checksum],
            properties: {
              purpose: { type: :string, enum: UploadedImage::PURPOSES },
              filename: { type: :string },
              content_type: { type: :string, enum: UploadedImage::CONTENT_TYPES },
              byte_size: { type: :integer, maximum: UploadedImage::MAX_BYTES },
              checksum: { type: :string, description: "Base64 MD5 of the bytes" }
            }
          }
        }
      }

      response "201", "upload slot" do
        schema type: :object, required: [ "data" ], properties: {
          data: {
            type: :object,
            required: %w[signed_id direct_upload],
            properties: {
              signed_id: { type: :string },
              direct_upload: {
                type: :object, required: %w[url headers],
                properties: { url: { type: :string }, headers: { type: :object, additionalProperties: { type: :string } } }
              }
            }
          }
        }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let(:body) { { upload: { purpose: "avatar", filename: "me.png", content_type: "image/png", byte_size: bytes.bytesize, checksum: checksum } } }

        run_test!
      end

      response "422", "not an allowed image" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let(:body) { { upload: { purpose: "avatar", filename: "x.pdf", content_type: "application/pdf", byte_size: 10, checksum: "x" } } }

        run_test! do
          expect(json_body.dig("error", "fields")).to have_key("content_type")
        end
      end
    end
  end

  it "hands back a blob only to its uploader, once the bytes have arrived" do
    post "/api/v1/uploads", headers: api_headers(user), as: :json,
                            params: { upload: { purpose: "avatar", filename: "me.png", content_type: "image/png", byte_size: bytes.bytesize, checksum: checksum } }
    slot = json_data

    expect { UploadedImage.find!(slot["signed_id"], user: user, purpose: "avatar") }
      .to raise_error(UploadedImage::Invalid, I18n.t("api.uploads.not_uploaded"))

    put slot.dig("direct_upload", "url"), params: bytes, headers: slot.dig("direct_upload", "headers")
    expect(response).to have_http_status(:no_content)

    expect(UploadedImage.find!(slot["signed_id"], user: user, purpose: "avatar")).to be_a(ActiveStorage::Blob)
    expect { UploadedImage.find!(slot["signed_id"], user: build_user, purpose: "avatar") }.to raise_error(UploadedImage::Invalid)
    expect { UploadedImage.find!(slot["signed_id"], user: user, purpose: "timeline_post") }.to raise_error(UploadedImage::Invalid)
  end
end
