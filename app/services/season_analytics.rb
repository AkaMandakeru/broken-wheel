# frozen_string_literal: true

# One door for every season funnel event.
#
# Every call site was spelling out `season_key:` and `season_id:` by hand, and a
# funnel is only as good as its property names: one typo'd or wrong-typed key
# drops an event out of the funnel it belongs to, and nobody notices until the
# month it was meant to measure is already over. (It happened here — the
# dismissal event was sending `season_id` as a string while every other event
# sent an integer.)
#
# Delegates to Analytics, which handles the PostHog fan-out and swallows its own
# errors, so a tracking failure can never break the flow it sits in.
class SeasonAnalytics
  def self.track(user:, event:, season:, **properties)
    Analytics.track(
      user: user,
      event: event,
      properties: { season_key: season&.key, season_id: season&.id }.merge(properties)
    )
  end
end
