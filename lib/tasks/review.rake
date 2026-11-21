# frozen_string_literal: true

require "securerandom"

namespace :review do
  desc "Create (or reset) the account app-store reviewers sign in with. " \
       "Usage: rails 'review:account[email]' (REVIEW_PASSWORD=... to choose the password)"
  task :account, [ :email ] => :environment do |_t, args|
    email = (args[:email].presence || "play-review@mandakeru-labs.com").downcase.strip
    password = ENV["REVIEW_PASSWORD"].presence || SecureRandom.alphanumeric(16)

    # Saved directly rather than through Accounts::Registration, so it doesn't
    # announce a fake signup in Slack or count in the signup funnel. Running it
    # again resets the password and unlocks the account, in case a reviewer
    # locked it out with wrong guesses.
    user = User.find_or_initialize_by(email: email)
    created = user.new_record?
    user.assign_attributes(
      first_name: user.first_name.presence || "Google Play",
      last_name: user.last_name.presence || "Reviewer",
      password: password,
      password_confirmation: password,
      locked_at: nil,
      failed_attempts: 0,
      unlock_token: nil
    )

    abort "Could not save #{email}: #{user.errors.full_messages.to_sentence}" unless user.save

    puts "#{created ? 'Created' : 'Reset'} the review account (user ##{user.id})."
    puts
    puts "  Email   : #{user.email}"
    puts "  Password: #{password}"
    puts
    puts "Put these under Play Console → App content → App access. Strava isn't"
    puts "needed: workouts can be logged by hand."
  end
end
