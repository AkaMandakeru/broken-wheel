# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 auth passwords", type: :request do
  path "/api/v1/auth/password" do
    post "Email a password reset link (opens the web reset page)" do
      tags "Auth"
      security []
      consumes "application/json"
      parameter name: :body, in: :body, schema: { type: :object, required: [ "email" ], properties: { email: { type: :string } } }

      response "202", "accepted, whether or not the email has an account" do
        let(:user) { build_user }
        let(:body) { { email: user.email } }

        run_test! do
          expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email ])
        end
      end
    end
  end

  it "does not reveal unknown emails" do
    post "/api/v1/auth/password", params: { email: "nobody@example.com" }, as: :json

    expect(response).to have_http_status(:accepted)
  end
end
