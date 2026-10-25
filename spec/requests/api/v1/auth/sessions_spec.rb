# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 auth sessions", type: :request do
  let(:user) { build_user(email: "ana@example.com", password: "secret123", password_confirmation: "secret123") }

  path "/api/v1/auth/login" do
    post "Log in with email and password" do
      tags "Auth"
      security []
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[email password],
        properties: {
          email: { type: :string }, password: { type: :string },
          device_name: { type: :string }, platform: { type: :string, example: "ios" }
        }
      }

      response "201", "signed in" do
        schema type: :object, required: [ "data" ], properties: { data: { "$ref" => "#/components/schemas/session" } }
        let(:body) { { email: user.email, password: "secret123", device_name: "iPhone", platform: "ios" } }

        run_test! do
          tokens = json_data
          expect(tokens["user"]["id"]).to eq(user.id)
          expect(ApiSession.authenticate_access(tokens["access_token"]).user).to eq(user)
          expect(ApiSession.last).to have_attributes(device_name: "iPhone", platform: "ios")
        end
      end

      response "401", "wrong password" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { email: user.email, password: "nope" } }

        run_test! do
          expect(json_error_code).to eq("invalid_credentials")
          expect(user.reload.failed_attempts).to eq(1)
        end
      end
    end
  end

  it "locks the account like Devise does on the web" do
    user.update_columns(failed_attempts: Devise.maximum_attempts - 1)

    post "/api/v1/auth/login", params: { email: user.email, password: "nope" }, as: :json
    expect(user.reload).to be_access_locked

    post "/api/v1/auth/login", params: { email: user.email, password: "secret123" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(json_error_code).to eq("account_locked")
  end

  it "answers in the language the app asks for" do
    post "/api/v1/auth/login", params: { email: user.email, password: "nope" }, as: :json,
                               headers: { "Accept-Language" => "pt-BR,pt;q=0.9" }

    expect(json_body.dig("error", "message")).to eq(I18n.t("api.errors.invalid_credentials", locale: :pt))
  end

  path "/api/v1/auth/refresh" do
    post "Swap a refresh token for new tokens (rotating)" do
      tags "Auth"
      security []
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object, required: [ "refresh_token" ], properties: { refresh_token: { type: :string } }
      }

      response "200", "new tokens" do
        schema type: :object, required: [ "data" ], properties: { data: { "$ref" => "#/components/schemas/session" } }
        let(:body) { { refresh_token: api_sign_in(user).refresh_token } }

        run_test! do
          expect(json_data["refresh_token"]).not_to eq(body[:refresh_token])
        end
      end

      response "401", "unknown, expired or revoked" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { refresh_token: "nope" } }

        run_test!
      end
    end
  end

  it "revokes the whole family when a rotated refresh token is used again" do
    first = api_sign_in(user)
    post "/api/v1/auth/refresh", params: { refresh_token: first.refresh_token }, as: :json
    second = json_data

    travel ApiSession::REUSE_GRACE + 1.second do
      post "/api/v1/auth/refresh", params: { refresh_token: first.refresh_token }, as: :json
      expect(response).to have_http_status(:unauthorized)

      expect(ApiSession.authenticate_access(second["access_token"])).to be_nil
    end
  end

  path "/api/v1/auth/logout" do
    delete "Log out this device" do
      tags "Auth"

      response "204", "signed out" do
        let(:tokens) { api_sign_in(user) }
        let(:Authorization) { "Bearer #{tokens.access_token}" }

        run_test! do
          expect(ApiSession.authenticate_access(tokens.access_token)).to be_nil
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { "Bearer nope" }

        run_test!
      end
    end
  end

  it "signs every device out when the password changes" do
    tokens = api_sign_in(user)

    user.update!(password: "another123", password_confirmation: "another123")

    expect(ApiSession.authenticate_access(tokens.access_token)).to be_nil
  end

  it "turns away builds older than the minimum supported version" do
    tokens = api_sign_in(user)

    with_env("MOBILE_MIN_SUPPORTED_VERSION" => "2.0.0") do
      delete "/api/v1/auth/logout", headers: { "Authorization" => "Bearer #{tokens.access_token}", "X-App-Version" => "1.9.3" }
    end

    expect(response).to have_http_status(:upgrade_required)
    expect(json_error_code).to eq("upgrade_required")
  end

  def with_env(values)
    previous = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
