# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 blocks", type: :request do
  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
  let(:other) { build_user(first_name: "Troll") }

  path "/api/v1/blocks" do
    get "Players the viewer has blocked, most recent first" do
      tags "Moderation"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/cursor"
      parameter "$ref" => "#/components/parameters/limit"

      response "200", "blocked players" do
        schema SocialSchemas.page(SocialSchemas::USER_BLOCK)

        before do
          UserBlock.block!(user, other)
          UserBlock.block!(build_user, user)
        end

        run_test! do
          expect(json_data.map { |row| row["user"]["id"] }).to eq([ other.id ])
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }

        run_test!
      end
    end
  end

  path "/api/v1/blocks/{user_id}" do
    parameter name: :user_id, in: :path, schema: { type: :integer }

    post "Block a player (hides their posts and comments from you)" do
      tags "Moderation"
      description "Blocking someone already blocked returns the existing block with 200."
      produces "application/json"

      response "201", "blocked" do
        schema SocialSchemas.data(SocialSchemas::USER_BLOCK)
        let(:user_id) { other.id }

        run_test! do
          expect(user.blocked_users).to eq([ other ])
        end
      end

      response "200", "already blocked" do
        schema SocialSchemas.data(SocialSchemas::USER_BLOCK)
        let(:user_id) { other.id }
        before { UserBlock.block!(user, other) }

        run_test! do
          expect(UserBlock.count).to eq(1)
        end
      end

      response "422", "yourself" do
        schema "$ref" => "#/components/schemas/error"
        let(:user_id) { user.id }

        run_test! do
          expect(json_error_code).to eq("cannot_block_self")
        end
      end

      response "404", "no such player" do
        schema "$ref" => "#/components/schemas/error"
        let(:user_id) { 0 }

        run_test!
      end
    end

    delete "Unblock a player" do
      tags "Moderation"

      response "204", "unblocked (also when they weren't blocked)" do
        let(:user_id) { other.id }
        before { UserBlock.block!(user, other) }

        run_test! do
          expect(user.user_blocks.reload).to be_empty
        end
      end
    end
  end
end
