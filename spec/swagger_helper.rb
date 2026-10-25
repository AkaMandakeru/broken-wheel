# frozen_string_literal: true

require "rails_helper"

# The mobile API's OpenAPI document is generated from the rswag request specs
# under spec/requests/api:
#
#   bundle exec rake rswag:specs:swaggerize PATTERN="spec/requests/api/**/*_spec.rb"
#
# writes openapi/v1/openapi.yaml, which the mobile app builds its types from.
# CI fails when the committed file is out of date (config/ci.rb).
RSpec.configure do |config|
  config.openapi_root = Rails.root.join("openapi").to_s
  config.openapi_format = :yaml

  nullable_string = { type: :string, nullable: true }

  config.openapi_specs = {
    "v1/openapi.yaml" => {
      openapi: "3.0.3",
      info: {
        title: "Sports Communities API",
        version: "v1",
        description: "Mobile API. Every success body is `{ data, meta? }`; every error is `{ error: { code, message, fields? } }`."
      },
      servers: [ { url: "/" } ],
      security: [ { bearer: [] } ],
      paths: {},
      components: {
        securitySchemes: {
          bearer: { type: :http, scheme: :bearer, description: "Access token from /api/v1/auth/login, valid 15 minutes" }
        },
        parameters: {
          accept_language: { name: "Accept-Language", in: :header, required: false, schema: { type: :string, example: "pt-BR" } },
          app_version: { name: "X-App-Version", in: :header, required: false, schema: { type: :string, example: "1.0.0" } },
          idempotency_key: { name: "Idempotency-Key", in: :header, required: false, schema: { type: :string, maxLength: 255 } },
          cursor: { name: :cursor, in: :query, required: false, schema: { type: :string }, description: "`meta.next_cursor` of the previous page" },
          limit: { name: :limit, in: :query, required: false, schema: { type: :integer, minimum: 1, maximum: 100 } }
        },
        schemas: {
          error: {
            type: :object,
            required: [ "error" ],
            properties: {
              error: {
                type: :object,
                required: %w[code message],
                properties: {
                  code: { type: :string },
                  message: { type: :string },
                  feature: { type: :string, description: "With `feature_disabled`: the switched-off feature's key" },
                  fields: { type: :object, additionalProperties: { type: :array, items: { type: :string } } }
                }
              }
            }
          },
          page_meta: {
            type: :object,
            required: [ "next_cursor" ],
            properties: { next_cursor: nullable_string }
          },
          # { "original": url, "<variant>": url } — null when there is no image.
          image: { type: :object, nullable: true, additionalProperties: { type: :string } },
          user_summary: {
            type: :object,
            required: %w[id first_name last_name display_name],
            properties: {
              id: { type: :integer },
              first_name: { type: :string },
              last_name: { type: :string },
              nickname: nullable_string,
              display_name: { type: :string },
              title: {
                type: :object, nullable: true,
                properties: { key: { type: :string }, label: { type: :string } }
              },
              avatar: { "$ref" => "#/components/schemas/image" }
            }
          },
          session: {
            type: :object,
            required: %w[token_type access_token refresh_token access_token_expires_at refresh_token_expires_at user],
            properties: {
              token_type: { type: :string, enum: [ "Bearer" ] },
              access_token: { type: :string },
              refresh_token: { type: :string },
              access_token_expires_at: { type: :string, format: "date-time" },
              refresh_token_expires_at: { type: :string, format: "date-time" },
              user: { "$ref" => "#/components/schemas/user_summary" }
            }
          }
        }
      }
    }
  }
end
