# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackNotifier do
  let(:user) { build_user(first_name: "Jean", last_name: "Silva", email: "jean@example.com") }
  let(:default_webhook) { "https://hooks.slack.com/services/T000/B000/default" }

  def delivered
    @delivered ||= []
  end

  before do
    # Capture what would be posted without touching the network.
    allow(SlackDeliveryJob).to receive(:perform_later) { |event_key, payload| delivered << [ event_key, payload ] }
  end

  def enable(**vars)
    stub_const("ENV", ENV.to_h.merge(
      "SLACK_WEBHOOK_URL" => default_webhook,
      "SLACK_NOTIFICATIONS_ENABLED" => "true"
    ).merge(vars))
  end

  describe "when it stays quiet" do
    # A developer machine or staging box must never post to the team channel.
    it "does nothing outside production by default" do
      stub_const("ENV", ENV.to_h.merge("SLACK_WEBHOOK_URL" => default_webhook))

      expect(described_class.notify(:user_registered, user: user)).to be(false)
      expect(delivered).to be_empty
    end

    it "does nothing when no webhook is configured" do
      stub_const("ENV", ENV.to_h.merge("SLACK_NOTIFICATIONS_ENABLED" => "true"))

      expect(described_class.notify(:user_registered, user: user)).to be(false)
    end

    it "does nothing for an unknown event" do
      enable

      expect(described_class.notify(:not_an_event, user: user)).to be(false)
    end

    it "does nothing without a user" do
      enable

      expect(described_class.notify(:user_registered, user: nil)).to be(false)
    end
  end

  describe "in production" do
    it "delivers even without the override" do
      stub_const("ENV", ENV.to_h.merge("SLACK_WEBHOOK_URL" => default_webhook))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      expect(described_class.notify(:user_registered, user: user)).to be(true)
    end
  end

  describe "the message" do
    before { enable }

    it "carries the event, name, email and date the request asked for" do
      described_class.notify(:user_registered, user: user)
      _url, payload = delivered.first
      fields = payload[:blocks].last[:fields].map { |f| f[:text] }

      expect(fields).to include(a_string_including("*Event*"), a_string_including("*User*\nJean Silva"),
                                a_string_including("*Email*\njean@example.com"), a_string_including("*Date*"))
    end

    # Tagged [TEST] here because the suite runs outside production; see the
    # environment tagging group below.
    it "includes a plain-text fallback for notification popups" do
      described_class.notify(:user_registered, user: user)
      _url, payload = delivered.first

      expect(payload[:text]).to eq("[TEST] 🎉 New user registered — Jean Silva (jean@example.com)")
    end

    it "adds per-event extras" do
      described_class.notify(:workout_imported, user: user, extra: { "Workouts" => 12 })
      _url, payload = delivered.first

      expect(payload[:blocks].last[:fields].map { |f| f[:text] }).to include(a_string_including("*Workouts*\n12"))
    end

    # Name is required at signup, but the notifier shouldn't produce a stray
    # " (email)" if it is ever blank.
    it "falls back to the email when the user has no name" do
      nameless = build_user(email: "noname@example.com")
      allow(nameless).to receive_messages(first_name: nil, last_name: nil)

      described_class.notify(:user_registered, user: nameless)

      expect(delivered.first.last[:text]).to include("noname@example.com")
    end
  end

  describe "routing" do
    # The webhook is a credential and job arguments are stored in the database,
    # so the job is handed the event key and resolves the URL itself.
    it "enqueues the event key, never the webhook URL" do
      enable
      described_class.notify(:premium_granted, user: user)

      expect(delivered.first.first).to eq(:premium_granted)
      expect(delivered.first.flatten.map(&:to_s).join).not_to include("hooks.slack.com")
    end

    it "resolves the default webhook at send time" do
      enable

      expect(Slack::Config.webhook_url_for(:premium_granted)).to eq(default_webhook)
    end

    it "prefers a per-event webhook when one is set" do
      enable("SLACK_WEBHOOK_URL_PREMIUM_GRANTED" => "https://hooks.slack.com/services/T000/B111/premium")

      expect(Slack::Config.webhook_url_for(:premium_granted)).to end_with("/premium")
      expect(Slack::Config.webhook_url_for(:user_registered)).to eq(default_webhook)
    end
  end

  describe "the payload shape" do
    before { enable }

    # Matches the minimal form a webhook is known to accept.
    it "sends text and blocks and nothing else by default" do
      described_class.notify(:user_registered, user: user)

      expect(delivered.first.last.keys).to contain_exactly(:text, :blocks)
    end

    # A modern webhook ignores these without chat:write.customize, and a channel
    # the app isn't in fails the whole post.
    it "omits channel and username unless configured" do
      described_class.notify(:user_registered, user: user)
      payload = delivered.first.last

      expect(payload).not_to have_key(:channel)
      expect(payload).not_to have_key(:username)
    end

    it "includes them once they are set" do
      enable("SLACK_CHANNEL" => "#ops", "SLACK_USERNAME" => "Broken Wheels")
      described_class.notify(:user_registered, user: user)

      expect(delivered.first.last).to include(channel: "#ops", username: "Broken Wheels")
    end
  end

  describe "environment tagging" do
    # Staging normally runs with RAILS_ENV=production, so Rails.env can't tell
    # the two apart — SLACK_ENVIRONMENT names the deployment explicitly.
    it "tags a staging message so it can't be mistaken for a real signup" do
      enable("SLACK_ENVIRONMENT" => "staging")
      described_class.notify(:user_registered, user: user)
      payload = delivered.first.last

      expect(payload[:text]).to start_with("[STG] ")
      expect(payload[:blocks].first[:text][:text]).to start_with("[STG] ")
    end

    it "tags development" do
      enable("SLACK_ENVIRONMENT" => "development")
      described_class.notify(:user_registered, user: user)

      expect(delivered.first.last[:text]).to start_with("[DEV] ")
    end

    it "upcases an environment it doesn't know" do
      enable("SLACK_ENVIRONMENT" => "qa")
      described_class.notify(:user_registered, user: user)

      expect(delivered.first.last[:text]).to start_with("[QA] ")
    end

    it "leaves production untagged" do
      enable("SLACK_ENVIRONMENT" => "production")
      described_class.notify(:user_registered, user: user)

      expect(delivered.first.last[:text]).to start_with("🎉")
    end

    # Setting the deployment name is itself the opt-in.
    it "enables notifications outside production on its own" do
      stub_const("ENV", ENV.to_h.merge(
        "SLACK_WEBHOOK_URL" => default_webhook,
        "SLACK_ENVIRONMENT" => "staging"
      ).except("SLACK_NOTIFICATIONS_ENABLED"))

      expect(described_class.notify(:user_registered, user: user)).to be(true)
    end

    it "still tags when enabled by the boolean instead" do
      stub_const("ENV", ENV.to_h.merge(
        "SLACK_WEBHOOK_URL" => default_webhook,
        "SLACK_NOTIFICATIONS_ENABLED" => "true"
      ).except("SLACK_ENVIRONMENT"))

      described_class.notify(:user_registered, user: user)

      # Falls back to Rails.env, which is `test` here.
      expect(delivered.first.last[:text]).to start_with("[TEST] ")
    end
  end

  describe Slack::Config do
    it "reports status without ever exposing the webhook URL" do
      enable("SLACK_CHANNEL" => "#ops")

      expect(described_class.status).to include(enabled: true, default_webhook: true, channel: "#ops")
      expect(described_class.status.values.map(&:to_s).join).not_to include("hooks.slack.com")
    end
  end
end

RSpec.describe SlackDeliveryJob do
  before do
    stub_const("ENV", ENV.to_h.merge("SLACK_WEBHOOK_URL" => "https://hooks.slack.com/services/T/B/x"))
  end

  # A notification must never take down the action that triggered it.
  it "swallows and logs a network failure" do
    allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)
    expect(Rails.logger).to receive(:warn).with(/Slack delivery error/)

    expect { described_class.new.perform(:user_registered, { text: "hi" }) }.not_to raise_error
  end

  it "logs a non-success response" do
    response = Net::HTTPBadRequest.new("1.1", "400", "Bad Request")
    allow(response).to receive(:body).and_return("invalid_payload")
    allow(Net::HTTP).to receive(:start).and_return(response)
    expect(Rails.logger).to receive(:warn).with(/Slack delivery failed for user_registered: 400/)

    described_class.new.perform(:user_registered, { text: "hi" })
  end

  it "does nothing when no webhook is configured for the event" do
    stub_const("ENV", ENV.to_h.except("SLACK_WEBHOOK_URL"))
    expect(Net::HTTP).not_to receive(:start)

    described_class.new.perform(:user_registered, { text: "hi" })
  end
end
