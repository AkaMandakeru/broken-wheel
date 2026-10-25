# frozen_string_literal: true

# Preview at /rails/mailers/engagement_mailer (development only). Uses the
# first special challenge and the first user in the database, so import a
# season blueprint first.
class EngagementMailerPreview < ActionMailer::Preview
  def special_event_reminder
    EngagementMailer.with(
      user: User.first,
      season_challenge: SeasonChallenge.special.order(:starts_at).first
    ).special_event_reminder
  end
end
