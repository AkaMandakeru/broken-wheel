# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 content reports", type: :request do
  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
  let(:author) { build_user(first_name: "Troll") }
  let(:challenge) { build_challenge(key: "reports_test", requirements: [ { metric: "distance_km", target: 1 } ]) }
  let(:timeline_post) { challenge.timeline_posts.create!(user: author, content: "Buy followers at spam.example") }

  path "/api/v1/reports" do
    post "Report a post, comment, club or player for the team to review" do
      tags "Moderation"
      description "Reporting the same thing again returns the existing report with 200."
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object, required: %w[reportable_type reportable_id reason],
        properties: {
          reportable_type: { type: :string, enum: ContentReport::REPORTABLE_TYPES.keys },
          reportable_id: { type: :integer },
          reason: { type: :string, enum: ContentReport::REASONS },
          details: { type: :string, maxLength: 2000 }
        }
      }

      response "201", "reported" do
        schema SocialSchemas.data(SocialSchemas::CONTENT_REPORT)
        let(:body) { { reportable_type: "timeline_post", reportable_id: timeline_post.id, reason: "spam", details: "Link spam" } }

        run_test! do
          expect(json_data).to include("reportable_type" => "timeline_post", "status" => "open")
          expect(ContentReport.last).to have_attributes(reporter: user, reported_user: author, reportable: timeline_post)
        end
      end

      response "200", "already reported" do
        schema SocialSchemas.data(SocialSchemas::CONTENT_REPORT)
        let(:body) { { reportable_type: "timeline_post", reportable_id: timeline_post.id, reason: "hate" } }
        let!(:existing) { ContentReport.file(reporter: user, reportable: timeline_post, reason: "spam").first }

        run_test! do
          expect(json_data).to include("id" => existing.id, "reason" => "spam")
          expect(ContentReport.count).to eq(1)
        end
      end

      response "422", "unknown reason" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { reportable_type: "timeline_post", reportable_id: timeline_post.id, reason: "boring" } }

        run_test! do
          expect(json_body.dig("error", "fields")).to have_key("reason")
        end
      end

      response "422", "not something that can be reported" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { reportable_type: "season", reportable_id: 1, reason: "spam" } }

        run_test! do
          expect(json_body.dig("error", "fields")).to have_key("reportable_type")
        end
      end

      response "404", "no such content" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { reportable_type: "timeline_post_comment", reportable_id: 0, reason: "spam" } }

        run_test!
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }
        let(:body) { { reportable_type: "user", reportable_id: author.id, reason: "harassment" } }

        run_test!
      end
    end
  end

  it "points every kind of report at the person responsible" do
    comment = timeline_post.timeline_post_comments.create!(user: author, content: "Rude")
    club = Club.new(name: "Bad club").tap { |c| Clubs::Membership.create_with_founder(c, author) }

    [ [ "timeline_post_comment", comment.id ], [ "club", club.id ], [ "user", author.id ] ].each do |type, id|
      post "/api/v1/reports", headers: api_headers(user), as: :json, params: { reportable_type: type, reportable_id: id, reason: "harassment" }
      expect(response).to have_http_status(:created)
    end

    expect(ContentReport.pluck(:reported_user_id).uniq).to eq([ author.id ])
  end

  it "refuses a report about yourself" do
    post "/api/v1/reports", headers: api_headers(user), as: :json, params: { reportable_type: "user", reportable_id: user.id, reason: "spam" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_error_code).to eq("cannot_report_self")
  end

  it "tells the team on Slack" do
    slack_env(SLACK_WEBHOOK_URL: "https://hooks.slack.com/services/T/B/X", SLACK_NOTIFICATIONS_ENABLED: "true")

    expect {
      post "/api/v1/reports", headers: api_headers(user), as: :json,
                              params: { reportable_type: "timeline_post", reportable_id: timeline_post.id, reason: "spam" }
    }.to have_enqueued_job(SlackDeliveryJob).with(:content_reported, anything)
  end
end
