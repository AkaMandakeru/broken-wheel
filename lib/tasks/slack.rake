# frozen_string_literal: true

namespace :slack do
  desc "Show Slack notification config (never prints the webhook URL)"
  task status: :environment do
    status = Slack::Config.status

    puts "Slack notifications"
    puts "  deployment       : #{status[:environment]}#{" (RAILS_ENV=#{status[:rails_env]})" if status[:environment] != status[:rails_env]}"
    puts "  message tag      : #{status[:tag] ? "[#{status[:tag]}]" : 'none (production)'}"
    puts "  enabled          : #{status[:enabled] ? 'yes' : 'no'}"
    puts "  forced on        : #{status[:forced_on] ? 'yes (SLACK_NOTIFICATIONS_ENABLED)' : 'no'}"
    puts "  default webhook  : #{status[:default_webhook] ? 'set' : 'missing'}"
    puts "  per-event hooks  : #{status[:per_event_webhooks].presence&.join(', ') || 'none'}"
    puts "  channel override : #{status[:channel] || 'none (posts to the webhook default)'}"
    puts
    puts "Events: #{Slack::Event.keys.join(', ')}"

    unless status[:enabled]
      puts
      puts "Nothing will be sent. Set SLACK_WEBHOOK_URL, and outside production"
      puts "also SLACK_ENVIRONMENT=staging (or development) — which both enables"
      puts "notifications and tags them, so a test is never mistaken for the real thing."
    end
  end

  desc "Send a real test message. Usage: rails 'slack:test[user_registered]'"
  task :test, [ :event ] => :environment do |_t, args|
    event = (args[:event].presence || "user_registered").to_sym

    unless Slack::Event.exists?(event)
      abort "Unknown event #{event.inspect}. Options: #{Slack::Event.keys.join(', ')}"
    end

    unless Slack::Config.enabled?
      abort "Slack is off here. Set SLACK_WEBHOOK_URL and SLACK_NOTIFICATIONS_ENABLED=true, " \
            "then run `rails slack:status` to confirm."
    end

    user = User.first
    abort "No users to build a sample message from." if user.nil?

    # Delivered inline so the result is visible right here rather than in a
    # worker log.
    payload = SlackNotifier.new(event, user: user, extra: { "Test" => "yes" }).send(:payload)
    SlackDeliveryJob.new.perform(event, payload)

    puts "Sent a #{event} test message. Check the channel — if nothing arrived,"
    puts "the reason is in the log (invalid_payload, channel_not_found, no_service)."
  end
end
