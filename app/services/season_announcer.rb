# frozen_string_literal: true

# Announces a season that has just opened.
#
# Reach is the whole point here, so this fans out across every channel we have
# rather than relying on push alone — only a fraction of players have granted
# notification permission, and the in-app banner is what the rest will see.
#
# Announcing is stamped on the season, so activating it twice, a retried job, or
# a re-import never notifies everyone a second time.
class SeasonAnnouncer
  def self.call(season, force: false)
    new(season).call(force: force)
  end

  def initialize(season)
    @season = season
  end

  def call(force: false)
    return false unless announceable?(force)

    # Claim first: two workers activating the same season must not both send.
    return false unless claim(force)

    push_to_subscribers
    notify_team
    record_activity
    true
  end

  private

  def announceable?(force)
    return false unless @season.active?
    return true if force

    @season.announced_at.nil?
  end

  def claim(force)
    scope = Season.where(id: @season.id)
    scope = scope.where(announced_at: nil) unless force

    claimed = scope.update_all(announced_at: Time.current, updated_at: Time.current).positive?
    @season.reload if claimed
    claimed
  end

  # Everyone who has granted permission. The in-app banner covers the rest.
  def push_to_subscribers
    PushNotifier.broadcast(
      title: I18n.t("push.season_started.title"),
      body: I18n.t("push.season_started.body", season: @season.name),
      path: Rails.application.routes.url_helpers.season_path(@season),
      tag: "season-#{@season.id}-started"
    )
  end

  def notify_team
    SlackNotifier.notify(
      :season_started,
      user: nil,
      subject: @season.name,
      extra: {
        "Season" => @season.name,
        "Runs" => [ @season.starts_at&.to_date, @season.ends_at&.to_date ].compact.join(" → "),
        "Levels" => @season.max_level
      }
    )
  end

  # Shows up in the season's own activity feed, so there is a record of when it
  # opened rather than only a notification that has already been dismissed.
  def record_activity
    SeasonActivity.create!(
      season: @season,
      kind: "season_started",
      metadata: { name: @season.name, starts_at: @season.starts_at&.to_date&.to_s }
    )
  end
end
