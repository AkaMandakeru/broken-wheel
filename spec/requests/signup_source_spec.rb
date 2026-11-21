# frozen_string_literal: true

require "rails_helper"

# The team's Slack signup alert says whether a player joined from the website
# or the app.
RSpec.describe "Signup source in the Slack alert", type: :request do
  let(:sources) { [] }

  before do
    allow(SlackNotifier).to receive(:notify) do |event, extra: {}, **|
      sources << extra["Source"] if event == :user_registered
    end
  end

  it "is Web for the website's sign-up form" do
    post user_registration_path, params: {
      user: { first_name: "Ana", last_name: "Lima", email: "ana@example.com",
              password: "secret123", password_confirmation: "secret123" }
    }

    expect(User.find_by(email: "ana@example.com")).to be_present
    expect(sources).to eq([ "Web" ])
  end

  it "is App, with the platform and version, for the app's sign-up" do
    post "/api/v1/auth/register",
         params: { user: { first_name: "Ana", last_name: "Lima", email: "ana@example.com", password: "secret123" },
                   platform: "android" },
         headers: { "X-App-Version" => "1.0.0" },
         as: :json

    expect(response).to have_http_status(:created)
    expect(sources).to eq([ "App · android · v1.0.0" ])
  end

  it "is still App when the app sends nothing about itself" do
    post "/api/v1/auth/register",
         params: { user: { first_name: "Ana", last_name: "Lima", email: "ana@example.com", password: "secret123" } },
         as: :json

    expect(response).to have_http_status(:created)
    expect(sources).to eq([ "App" ])
  end
end
