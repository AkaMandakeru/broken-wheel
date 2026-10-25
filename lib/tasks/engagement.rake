# frozen_string_literal: true

namespace :engagement do
  # For schedulers outside Solid Queue (e.g. Heroku Scheduler, daily). Delivers
  # inline: production uses the :async adapter, whose in-process threads die
  # with this one-off process — anything merely enqueued would never be sent.
  desc "Email players about special events coming up in the next few days"
  task special_event_reminders: :environment do
    ActiveJob::Base.queue_adapter = :inline

    due = SpecialEventReminder.due
    due.each do |season_challenge|
      count = SpecialEventReminder.call(season_challenge)
      puts "✉️  #{season_challenge.challenge.display_title}: #{count || 0} reminder(s) sent"
    end
    puts "No special events due for a reminder." if due.empty?
  end
end
