# frozen_string_literal: true

module Accounts
  # Signing up, from the web form or the app. The model does the account
  # itself (validations, default titles); this adds the announcements, so both
  # paths count in the same funnel and post to the same Slack channel.
  class Registration
    WEB = "Web"

    def self.call(attributes, source:) = new(attributes, source: source).call

    # For Devise's controller, which saves the user itself. `source` says where
    # the signup came from ("Web", "App · android · v1.2.0"), so the team can
    # tell the two apart in Slack.
    def self.announce(user, source:)
      Analytics.track(user: user, event: "user_signed_up")
      Analytics.identify(user: user)
      SlackNotifier.notify(:user_registered, user: user, extra: { "Source" => source })
    end

    # "App", plus whatever the client told us about itself.
    def self.app_source(platform: nil, app_version: nil)
      details = [ platform.to_s.strip.first(20).presence, app_version.presence && "v#{app_version.to_s.strip.first(20)}" ]
      [ "App", *details.compact ].join(" · ")
    end

    def initialize(attributes, source:)
      @attributes = attributes
      @source = source
    end

    # The saved user, or an unsaved one carrying its errors.
    def call
      user = User.new(@attributes)
      self.class.announce(user, source: @source) if user.save
      user
    end
  end
end
