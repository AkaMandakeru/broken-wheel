# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Email subscriptions", type: :request do
  let(:user) { build_user }
  let(:token) { user.generate_token_for(:email_unsubscribe) }

  # Mail scanners prefetch every link in a message.
  it "only shows the page on GET, without unsubscribing" do
    get email_unsubscribe_path(token: token)

    expect(response).to have_http_status(:ok)
    expect(user.reload.email_reminders?).to be(true)
  end

  it "unsubscribes from the page's button" do
    post email_unsubscribe_path(token: token)

    expect(response).to redirect_to(email_unsubscribe_path(token: token))
    expect(user.reload.email_reminders?).to be(false)
  end

  it "accepts the mail client's one-click unsubscribe" do
    post email_unsubscribe_path(token: token), params: { "List-Unsubscribe" => "One-Click" }

    expect(response).to have_http_status(:ok)
    expect(user.reload.email_reminders?).to be(false)
  end

  it "subscribes again" do
    user.unsubscribe_from_emails!

    delete email_unsubscribe_path(token: token)

    expect(user.reload.email_reminders?).to be(true)
  end

  it "rejects a forged token" do
    post email_unsubscribe_path(token: "not-a-token")

    expect(response).to have_http_status(:not_found)
  end

  it "keeps working for players who are signed in elsewhere" do
    sign_in user
    get email_unsubscribe_path(token: token)

    expect(response).to have_http_status(:ok)
  end

  describe "the profile toggle" do
    before { sign_in user }

    it "turns reminder emails off and on" do
      patch profile_path, params: { user: { email_reminders: "0" } }
      expect(user.reload.email_reminders?).to be(false)
      expect(User.reachable_by_email).not_to include(user)

      patch profile_path, params: { user: { email_reminders: "1" } }
      expect(user.reload.email_reminders?).to be(true)
      expect(User.reachable_by_email).to include(user)
    end
  end
end
