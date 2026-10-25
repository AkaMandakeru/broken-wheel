# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 auth registrations", type: :request do
  path "/api/v1/auth/register" do
    post "Create an account and sign in" do
      tags "Auth"
      security []
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: [ "user" ],
        properties: {
          user: {
            type: :object,
            required: %w[first_name last_name email password],
            properties: {
              first_name: { type: :string }, last_name: { type: :string }, nickname: { type: :string },
              email: { type: :string }, password: { type: :string, minLength: 6, maxLength: 128 }
            }
          },
          device_name: { type: :string }, platform: { type: :string }
        }
      }

      response "201", "account created" do
        schema type: :object, required: [ "data" ], properties: { data: { "$ref" => "#/components/schemas/session" } }
        let(:body) { { user: { first_name: "Ana", last_name: "Lima", email: "ana@example.com", password: "secret123" } } }

        run_test! do
          user = User.find_by!(email: "ana@example.com")
          expect(json_data["user"]["id"]).to eq(user.id)
          expect(user.titles).to match_array(Titles.defaults.map(&:to_sym))
          expect(AnalyticsEvent.where(user: user, event_name: "user_signed_up")).to exist
        end
      end

      response "422", "invalid" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { user: { first_name: "", last_name: "Lima", email: "bad", password: "1" } } }

        run_test! do
          expect(json_error_code).to eq("validation_failed")
          expect(json_body.dig("error", "fields").keys).to include("first_name", "email", "password")
        end
      end
    end
  end

  it "translates errors rendered by rescue_from handlers, outside the locale's around_action" do
    allow(Accounts::Registration).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(User.new.tap(&:validate)))

    post "/api/v1/auth/register", params: { user: { first_name: "x", last_name: "y", email: "z@example.com", password: "secret123" } },
                                  as: :json, headers: { "Accept-Language" => "pt-BR" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body.dig("error", "message")).to eq(I18n.t("api.errors.validation_failed", locale: :pt))
  end
end
