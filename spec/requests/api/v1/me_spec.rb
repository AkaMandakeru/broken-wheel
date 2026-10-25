# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 me", type: :request do
  include ActiveJob::TestHelper

  let(:user) { build_user(first_name: "Ana", last_name: "Silva", nickname: "aninha", phone: "+55 11 99999-0000") }

  path "/api/v1/me" do
    get "The signed-in player's own profile" do
      tags "Me"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/accept_language"

      response "200", "profile" do
        schema type: :object, required: [ "data" ], properties: { data: ProfileSchemas::ME }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        before do
          user.update!(title: "rookie")
          grant_cosmetic(user, build_cosmetic(key: "gold_name", kind: "name_color", rarity: "epic", css_class: "text-amber-500"))
          user.equip_cosmetic!("name_color", "gold_name")
          grant_cosmetic(user, attach_cosmetic_art(build_cosmetic(key: "laurel", kind: "frame", rarity: "legendary")))
          user.equip_cosmetic!("frame", "laurel")
        end

        run_test! do
          me = json_data
          expect(me).to include("email" => user.email, "nickname" => "aninha", "phone" => "+55 11 99999-0000", "coins" => 0)
          expect(me["title"]).to eq("key" => "rookie", "label" => "Rookie")
          expect(me["available_titles"].pluck("key")).to include("rookie", "daily_runner")
          expect(me.dig("equipped", "name_color", "render")).to eq("type" => "solid", "colors" => [ CosmeticStyle::PALETTE["amber-500"] ])
          expect(me.dig("equipped", "frame", "image")).to include("original", "display")
          expect(me.dig("equipped", "banner")).to be_nil
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }

        run_test!
      end
    end

    patch "Update the profile and preferences" do
      tags "Me"
      consumes "application/json"
      produces "application/json"
      description "Send only the fields that change. `title` must be one the player has earned."
      parameter name: :body, in: :body, schema: ProfileSchemas::ME_UPDATE

      response "200", "updated" do
        schema type: :object, required: [ "data" ], properties: { data: ProfileSchemas::ME }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let(:body) { { user: { nickname: "ana.run", sports: %w[run bike], title: "daily_runner", email_reminders: false, locale: "pt" } } }

        run_test! do
          expect(json_data).to include("nickname" => "ana.run", "sports" => %w[run bike], "email_reminders" => false, "locale" => "pt")
          expect(json_data["title"]).to eq("key" => "daily_runner", "label" => "Daily Runner")
          expect(user.reload).to have_attributes(nickname: "ana.run", title: "daily_runner", email_reminders?: false, email_locale: :pt)
        end
      end

      response "422", "a title the player hasn't earned" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
        let(:body) { { user: { title: "champion" } } }

        run_test! do
          expect(json_error_code).to eq("validation_failed")
          expect(json_body.dig("error", "fields")).to have_key("title")
          expect(user.reload.title).to be_nil
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }
        let(:body) { { user: { nickname: "x" } } }

        run_test!
      end
    end

    delete "Delete the account" do
      tags "Me"
      description "Signs the player out everywhere and locks the account at once; the data is deleted in the background " \
                  "(App Store guideline 5.1.1(v))."

      response "202", "deletion scheduled" do
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        run_test! do
          expect(Accounts::DeletionJob).to have_been_enqueued.with(user.id)
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }

        run_test!
      end
    end
  end

  describe "PATCH /api/v1/me" do
    def patch_me(attributes, **headers)
      patch "/api/v1/me", params: { user: attributes }, headers: api_headers(user, **headers), as: :json
    end

    let(:bytes) { file_fixture("season_cover.png").binread }

    def upload_avatar
      post "/api/v1/uploads", headers: api_headers(user), as: :json, params: {
        upload: { purpose: "avatar", filename: "me.png", content_type: "image/png", byte_size: bytes.bytesize,
                  checksum: OpenSSL::Digest::MD5.base64digest(bytes) }
      }
      slot = json_data
      put slot.dig("direct_upload", "url"), params: bytes, headers: slot.dig("direct_upload", "headers")
      slot["signed_id"]
    end

    it "attaches an avatar the player uploaded directly, then removes it with null" do
      signed_id = upload_avatar

      patch_me({ avatar: signed_id })

      expect(response).to have_http_status(:ok)
      expect(user.reload.avatar).to be_attached
      expect(json_data["avatar"]).to include("original", "thumb", "medium")

      patch_me({ avatar: nil })

      expect(response).to have_http_status(:ok)
      expect(json_data["avatar"]).to be_nil
      expect(user.reload.avatar).not_to be_attached
    end

    it "refuses an upload made for something else" do
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "x.png", content_type: "image/png",
                                                    metadata: { "uploader_id" => user.id, "purpose" => "timeline_post" })

      patch_me({ avatar: blob.signed_id })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_error_code).to eq("invalid_upload")
      expect(user.reload.avatar).not_to be_attached
    end

    it "refuses someone else's upload" do
      other = build_user
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: "x.png", content_type: "image/png",
                                                    metadata: { "uploader_id" => other.id, "purpose" => "avatar" })

      patch_me({ avatar: blob.signed_id })

      expect(json_error_code).to eq("invalid_upload")
    end

    it "refuses a locale the app doesn't speak, and changes nothing else" do
      patch_me({ locale: "fr", nickname: "changed" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig("error", "fields")).to have_key("locale")
      expect(user.reload.nickname).to eq("aninha")
    end

    it "refuses a sport the app doesn't have" do
      patch_me({ sports: %w[run curling] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_body.dig("error", "fields")).to have_key("sports")
    end

    it "requires a name" do
      patch_me({ first_name: "" })

      expect(json_error_code).to eq("validation_failed")
      expect(json_body.dig("error", "fields")).to have_key("first_name")
    end

    it "ignores fields the profile form doesn't allow either" do
      patch_me({ coins: 9_999, email: "new@example.com", nickname: "ok" })

      expect(response).to have_http_status(:ok)
      expect(user.reload).to have_attributes(coins: 0, nickname: "ok")
      expect(user.email).not_to eq("new@example.com")
    end

    it "answers 400 with nothing to update" do
      patch "/api/v1/me", params: {}, headers: api_headers(user), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "DELETE /api/v1/me" do
    it "signs out every device and locks the account before the data goes" do
      other_device = api_sign_in(user)
      headers = api_headers(user)

      delete "/api/v1/me", headers: headers

      expect(response).to have_http_status(:accepted)
      expect(user.reload).to be_access_locked
      expect(ApiSession.authenticate_access(other_device.access_token)).to be_nil
      get "/api/v1/me", headers: headers
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/auth/login", params: { email: user.email, password: "password123" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "deletes the account once the job runs" do
      perform_enqueued_jobs { delete "/api/v1/me", headers: api_headers(user) }

      expect(User.exists?(user.id)).to be(false)
    end
  end
end
