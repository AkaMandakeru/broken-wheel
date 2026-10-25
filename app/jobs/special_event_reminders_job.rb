# frozen_string_literal: true

# Sends the reminder email for every special event coming up in the next few
# days. Safe to run as often as you like — each event is sent at most once.
class SpecialEventRemindersJob < ApplicationJob
  queue_as :default

  def perform
    SpecialEventReminder.due.each do |season_challenge|
      SpecialEventReminder.call(season_challenge)
    end
  end
end
