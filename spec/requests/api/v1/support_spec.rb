# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 support", type: :request do
  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

  def open_ticket(owner = user, subject: "Strava won't sync", body: "It says error 500")
    SupportDesk.open_ticket(owner, subject: subject, body: body, category: "bug", source: "integrations")
  end

  path "/api/v1/support/tickets" do
    get "The player's support tickets, latest activity first" do
      tags "Support"
      produces "application/json"

      response "200", "tickets" do
        schema SocialSchemas.list(SocialSchemas::SUPPORT_TICKET)

        before do
          open_ticket(subject: "Older").update_columns(last_message_at: 2.days.ago)
          open_ticket(subject: "Newer")
          open_ticket(build_user, subject: "Someone else's")
        end

        run_test! do
          expect(json_data.pluck("subject")).to eq([ "Newer", "Older" ])
        end
      end

      response "403", "support is switched off" do
        schema "$ref" => "#/components/schemas/error"
        before { FeatureFlag.set(:support, false) }

        run_test! do
          expect(json_error_code).to eq("feature_disabled")
        end
      end
    end

    post "Open a ticket with its first message" do
      tags "Support"
      consumes "application/json"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"
      parameter name: :body, in: :body, schema: {
        type: :object, required: [ "ticket" ],
        properties: {
          ticket: {
            type: :object, required: %w[subject body],
            properties: {
              subject: { type: :string, maxLength: 200 },
              body: { type: :string },
              category: { type: :string, enum: SupportTicket::CATEGORIES, default: "general" },
              source: { type: :string, enum: SupportTicket::SOURCES, default: "general", description: "Which screen the player asked for help from" }
            }
          }
        }
      }

      response "201", "opened" do
        schema SocialSchemas.data(SocialSchemas::SUPPORT_TICKET_DETAIL)
        let(:body) { { ticket: { subject: "Missing XP", body: "My run didn't count", category: "support", source: "challenges" } } }

        run_test! do
          expect(json_data).to include("subject" => "Missing XP", "status" => "open", "category" => "support")
          expect(json_data["messages"].map { |m| [ m["body"], m["from_admin"] ] }).to eq([ [ "My run didn't count", false ] ])
        end
      end

      response "422", "no subject or message" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { ticket: { subject: "", body: "" } } }

        run_test! do
          expect(json_body.dig("error", "fields").keys).to include("subject", "body")
          expect(SupportTicket.count).to eq(0)
        end
      end
    end
  end

  it "tracks a new ticket like the web" do
    allow(Analytics).to receive(:track)

    post "/api/v1/support/tickets", headers: api_headers(user), as: :json,
                                    params: { ticket: { subject: "Hi", body: "Hello" } }

    expect(Analytics).to have_received(:track).with(hash_including(event: "support_ticket_created"))
  end

  path "/api/v1/support/tickets/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }

    get "A ticket and its conversation" do
      tags "Support"
      produces "application/json"

      response "200", "the ticket" do
        schema SocialSchemas.data(SocialSchemas::SUPPORT_TICKET_DETAIL)
        let(:ticket) { open_ticket }
        let(:id) { ticket.id }

        before { ticket.support_messages.create!(user: build_user(admin: true), body: "Try reconnecting", from_admin: true) }

        run_test! do
          expect(json_data["status"]).to eq("answered")
          expect(json_data["messages"].pluck("from_admin")).to eq([ false, true ])
          expect(json_data["messages"].last).not_to have_key("user")
        end
      end

      response "404", "someone else's ticket" do
        schema "$ref" => "#/components/schemas/error"
        let(:id) { open_ticket(build_user).id }

        run_test!
      end
    end
  end

  path "/api/v1/support/tickets/{ticket_id}/messages" do
    parameter name: :ticket_id, in: :path, schema: { type: :integer }

    post "Reply to a ticket" do
      tags "Support"
      consumes "application/json"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"
      parameter name: :body, in: :body, schema: {
        type: :object, required: [ "message" ],
        properties: { message: { type: :object, required: [ "body" ], properties: { body: { type: :string } } } }
      }

      let(:ticket) { open_ticket }
      let(:ticket_id) { ticket.id }

      response "201", "sent" do
        schema SocialSchemas.data(SocialSchemas::SUPPORT_MESSAGE)
        let(:body) { { message: { body: "Still broken" } } }

        run_test! do
          expect(ticket.reload.support_messages_count).to eq(2)
          expect(ticket.status).to eq("open")
        end
      end

      response "422", "empty reply" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { message: { body: "" } } }

        run_test! do
          expect(json_body.dig("error", "fields")).to have_key("body")
        end
      end

      response "404", "someone else's ticket" do
        schema "$ref" => "#/components/schemas/error"
        let(:ticket_id) { open_ticket(build_user).id }
        let(:body) { { message: { body: "Hi" } } }

        run_test!
      end
    end
  end
end
