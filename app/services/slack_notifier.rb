# frozen_string_literal: true

# Posts operational events to Slack.
#
# Call sites stay one line and never block on Slack: the message is built here
# and the HTTP request happens in a background job, so a slow or broken webhook
# can't hold up a signup or an import.
#
# Silently does nothing outside production unless SLACK_NOTIFICATIONS_ENABLED is
# set — see Slack::Config.
class SlackNotifier
  def self.notify(event, user:, extra: {})
    new(event, user: user, extra: extra).call
  end

  def initialize(event, user:, extra: {})
    @event = Slack::Event.find(event)
    @user = user
    @extra = extra.compact
  end

  def call
    return false unless deliverable?

    # The event key, not the URL — see SlackDeliveryJob.
    SlackDeliveryJob.perform_later(@event.key, payload)
    true
  end

  private

  def deliverable?
    return false if @event.nil? || @user.nil?
    return false unless Slack::Config.enabled?

    webhook_url.present?
  end

  def webhook_url
    @webhook_url ||= Slack::Config.webhook_url_for(@event.key)
  end

  # Deliberately close to the minimal `{"text": "..."}` an incoming webhook
  # accepts. `channel` and `username` are only sent when explicitly configured:
  # a modern Slack app ignores them without the chat:write.customize scope, and
  # a `channel` the app isn't a member of fails the whole post with
  # channel_not_found.
  def payload
    {
      text: fallback_text,
      blocks: blocks,
      channel: Slack::Config.channel,
      username: Slack::Config.username
    }.compact
  end

  # What shows in the notification popup and on any client that can't render
  # blocks. Slack requires it whenever blocks are present.
  def fallback_text
    "#{tag}#{@event.emoji} #{@event.label} — #{display_name} (#{@user.email})"
  end

  def blocks
    [
      { type: "header", text: { type: "plain_text", text: "#{tag}#{@event.emoji} #{@event.label}", emoji: true } },
      { type: "section", fields: fields.map { |label, value| { type: "mrkdwn", text: "*#{label}*\n#{value}" } } }
    ]
  end

  # "[STG] " on anything that isn't production, so a test is never mistaken for
  # a real signup. Empty in production.
  def tag
    label = Slack::Config.environment_tag
    label ? "[#{label}] " : ""
  end

  def fields
    base = {
      "Event" => @event.label,
      "User" => display_name,
      "Email" => @user.email,
      "Date" => timestamp
    }
    # Slack renders at most 10 fields in a section.
    base.merge(@extra.transform_keys(&:to_s)).first(10).to_h
  end

  def display_name
    [ @user.first_name, @user.last_name ].compact_blank.join(" ").presence || @user.email
  end

  def timestamp
    Time.current.in_time_zone(Slack::Config.time_zone).strftime("%d %b %Y, %H:%M %Z")
  end
end
