# frozen_string_literal: true

# Recomputes a user's season progress from scratch (idempotent). XP comes from
# the durable completion ledger plus time-based bonuses, so it survives weekly
# challenge resets and can be re-run safely at any time.
class SeasonProgressService
  STREAK_XP_PER_WEEK      = 10
  STREAK_CAP_WEEKS        = 10
  CONSISTENCY_XP_PER_WEEK = 15
  CLUB_BONUS              = 25

  def self.ensure_participation(user, season)
    season.season_participations.find_or_create_by!(user: user)
  end

  def initialize(participation)
    @participation = participation
    @user = participation.user
    @season = participation.season
  end

  def recalculate
    challenges_xp  = @participation.season_challenge_completions.sum(:xp_awarded)
    streak_xp      = [ streak_weeks, STREAK_CAP_WEEKS ].min * STREAK_XP_PER_WEEK
    consistency_xp = consistency_weeks * CONSISTENCY_XP_PER_WEEK
    club_xp        = @user.club_memberships.exists? ? CLUB_BONUS : 0

    base  = challenges_xp + streak_xp + consistency_xp + club_xp
    total = (base * @season.xp_multiplier).round
    new_level = Leveling.level_for(total)
    old_level = @participation.level

    @participation.update!(
      xp: total,
      level: new_level,
      xp_breakdown: {
        challenges: challenges_xp,
        streak: streak_xp,
        consistency: consistency_xp,
        clubs: club_xp,
        multiplier: @season.xp_multiplier.to_f
      },
      last_recalculated_at: Time.current
    )

    sync_lifetime_xp
    handle_level_up(old_level, new_level) if new_level > old_level
    @participation
  end

  private

  def streak_weeks
    AchievementChecker.user_stats(@user)[:streak].to_i
  end

  def consistency_weeks
    return 0 unless @season.window

    @user.workouts
         .where(workout_date: @season.starts_at.to_date..@season.ends_at.to_date)
         .pluck(:workout_date)
         .compact
         .map { |d| d.beginning_of_week(:sunday) }
         .uniq
         .size
  end

  def sync_lifetime_xp
    @user.update_column(:lifetime_xp, @user.season_participations.sum(:xp))
  end

  def handle_level_up(_old_level, new_level)
    SeasonActivity.create!(season: @season, user: @user, kind: "level_up", metadata: { level: new_level })
    SeasonRewardGranter.new(@participation).grant_up_to(new_level)
    notify_level_up(new_level)
  end

  def notify_level_up(level)
    PushNotifier.notify(
      @user,
      title: I18n.t("push.season_level.title"),
      body: I18n.t("push.season_level.body", level: level, season: @season.name),
      path: Rails.application.routes.url_helpers.season_path(@season),
      tag: "season-#{@season.id}-level"
    )
  end
end
