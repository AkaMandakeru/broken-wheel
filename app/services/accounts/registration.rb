# frozen_string_literal: true

module Accounts
  # Signing up, from the web form or the app. The model does the account
  # itself (validations, default titles); this adds the announcements, so both
  # paths count in the same funnel and post to the same Slack channel.
  class Registration
    def self.call(attributes) = new(attributes).call

    # For Devise's controller, which saves the user itself.
    def self.announce(user)
      Analytics.track(user: user, event: "user_signed_up")
      Analytics.identify(user: user)
      SlackNotifier.notify(:user_registered, user: user)
    end

    def initialize(attributes)
      @attributes = attributes
    end

    # The saved user, or an unsaved one carrying its errors.
    def call
      user = User.new(@attributes)
      self.class.announce(user) if user.save
      user
    end
  end
end
