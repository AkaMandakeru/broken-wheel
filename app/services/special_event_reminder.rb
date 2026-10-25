# frozen_string_literal: true

# Emails every player a few days before a special event (a one-day special
# challenge such as Children's Day or Halloween), with the event's banner.
#
# Everyone reachable by email gets it, not only current season participants: a
# player joins the season with their first workout, so the people who have not
# joined yet are exactly the ones this is meant to bring back.
#
# Sending is stamped on the season challenge, so a retried job, a second
# scheduler run or two workers never email everyone twice.
class SpecialEventReminder
  def self.call(season_challenge, force: false)
    new(season_challenge).call(force: force)
  end

  # Every special event whose reminder should go out today.
  def self.due
    Season.active.flat_map do |season|
      today = season.current_date
      season.season_challenges.special.where(reminder_sent_at: nil)
            .includes(:challenge).select { |sc| sc.reminder_due?(today: today) }
    end
  end

  def self.recipients
    User.reachable_by_email
  end

  def initialize(season_challenge)
    @season_challenge = season_challenge
  end

  # Returns the number of emails queued, or false when nothing was sent.
  def call(force: false)
    return false unless @season_challenge.special?
    return false unless claim(force)

    count = 0
    self.class.recipients.find_each do |user|
      EngagementMailer.with(user: user, season_challenge: @season_challenge)
                      .special_event_reminder.deliver_later
      count += 1
    rescue StandardError => e
      # Delivering inline (the rake task), one bad address must not stop the
      # rest — the event is already claimed, so they would never be retried.
      Rails.logger.warn("Special event reminder to user #{user.id} failed: #{e.class}: #{e.message}")
    end
    count
  end

  private

  def claim(force)
    scope = SeasonChallenge.where(id: @season_challenge.id)
    scope = scope.where(reminder_sent_at: nil) unless force

    claimed = scope.update_all(reminder_sent_at: Time.current, updated_at: Time.current).positive?
    @season_challenge.reload if claimed
    claimed
  end
end
