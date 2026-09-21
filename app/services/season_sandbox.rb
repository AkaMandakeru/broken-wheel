# frozen_string_literal: true

# Puts test data into a season for one user, so a season can be seen filled —
# levels, rewards, medals, the leaderboard — before it has started, or without
# a month of real running.
#
# Nothing here pokes at totals directly. Every action writes the same ledger
# rows the season engine writes (completions, grants, coin transactions,
# activities) and then recalculates, so what the tester sees is what a player
# with that history would see. The only thing the engine has no ledger for is
# "just give them XP"; that lives in `season_participations.sandbox_xp`.
#
# What the engine gates on real time — challenge completions only count while a
# season is active, dailies only for today — the sandbox writes regardless.
#
# Only available in development, or where SEASON_SANDBOX_ENABLED is set (a
# staging box runs RAILS_ENV=production, so the environment name alone cannot
# tell it apart from the real thing).
class SeasonSandbox
  class Error < StandardError; end

  # Marks everything the sandbox creates, so a reset can remove it without
  # touching a single real workout or account.
  WORKOUT_PROVIDER = "sandbox"
  BOT_EMAIL_DOMAIN = "sandbox.invalid"

  MAX_WORKOUTS = 200
  MAX_BOTS = 50
  MAX_DAILY_DAYS = 120

  def self.enabled?
    return true if Rails.env.development?

    ActiveModel::Type::Boolean.new.cast(ENV["SEASON_SANDBOX_ENABLED"]) == true
  end

  def self.bots
    User.where("email LIKE ?", "%@#{BOT_EMAIL_DOMAIN}")
  end

  def self.bot?(user)
    user.email.to_s.end_with?("@#{BOT_EMAIL_DOMAIN}")
  end

  attr_reader :season, :user

  def initialize(season, user)
    @season = season
    @user = user
  end

  def participation
    @participation ||= season.season_participations.find_by(user: user)
  end

  def enrolled?
    participation.present?
  end

  # --- Joining ----------------------------------------------------------------

  def enroll!
    @participation = SeasonProgressService.ensure_participation(user, season)
    # Joining enrolls in the season's challenges after commit; do it now so the
    # rest of this request sees the rows.
    enroll_in_challenges
    recalculate!
  end

  # --- Workouts ---------------------------------------------------------------

  # Spreads `count` workouts across the given dates. Inserted without model
  # callbacks: a real workout pushes a notification and queues a recalc per row,
  # and a hundred of those is noise when this recalculates once at the end.
  def generate_workouts!(count:, sport: "run", min_km: 3, max_km: 12, from: nil, to: nil, random: Random.new)
    dates = workout_dates(from, to)
    count = count.to_i.clamp(1, MAX_WORKOUTS)
    min_km, max_km = [ min_km.to_f, max_km.to_f ].minmax
    raise Error, "Distance must be above zero." unless max_km.positive?

    rows = Array.new(count) do |i|
      date = dates[(i * dates.size) / count]
      workout_row(date, sport.presence || "run", random.rand(min_km..max_km).round(2), random)
    end
    Workout.insert_all!(rows)

    ensure_enrolled
    recompute_challenges
    record_challenges_the_workouts_finished
    recalculate!
    count
  end

  # --- Challenges, objectives, dailies ----------------------------------------

  # Completes the given season challenges (every one when `ids` is blank),
  # whatever the season's status and the challenge's unlock level. With `claim`
  # the XP is collected straight away; without it the claim button has
  # something to show.
  def complete_challenges!(ids: nil, claim: true)
    ensure_enrolled
    scope = season.season_challenges.includes(:challenge)
    scope = scope.where(id: ids) if ids.present?

    done = scope.count { |season_challenge| record_challenge_completion(season_challenge, claim: claim) }
    recalculate!
    done
  end

  def complete_objectives!(ids: nil)
    ensure_enrolled
    scope = season.season_objectives
    scope = scope.where(id: ids) if ids.present?
    completed = participation.season_objective_completions.pluck(:season_objective_id).to_set

    done = scope.count do |objective|
      next false if completed.include?(objective.id)

      SeasonObjectives.record_completion(participation, objective, season, user)
      true
    end
    recalculate!
    done
  end

  # Draws and completes the daily set for each of the last `days` days of the
  # season up to today (or its first days, when it has not started yet).
  def complete_dailies!(days:)
    ensure_enrolled
    evaluator = DailyChallenges::Evaluator.new(participation)
    raise Error, "This season has no daily challenge templates." unless DailyChallengeTemplate.active.for_season(season).exists?

    done = daily_dates(days).sum do |date|
      DailyChallenges::Assigner.call(user, season, date: date).reject(&:completed?).each do |assignment|
        evaluator.award(assignment, assignment.daily_challenge_template)
      end.size
    end
    recalculate!
    done
  end

  # --- XP, level, premium, rewards --------------------------------------------

  # Tops the player up to the first XP of `level`. Only ever adds sandbox XP —
  # a player who has already earned more stays where they are, and rewards
  # granted on the way up are kept (grants are never revoked, in the sandbox or
  # out of it).
  def set_level!(level)
    ensure_enrolled
    level = level.to_i.clamp(1, season.level_curve_object.max_level)
    recalculate!

    target_xp = season.level_curve_object.floor_for(level)
    earned = earned_raw_xp
    needed = (target_xp / season.xp_multiplier.to_f).ceil - earned
    participation.update!(sandbox_xp: [ needed, 0 ].max)
    recalculate!
  end

  def add_xp!(amount)
    ensure_enrolled
    participation.update!(sandbox_xp: [ participation.sandbox_xp + amount.to_i, 0 ].max)
    recalculate!
  end

  # Going premium grants the premium track retroactively, as it does for a real
  # purchase. Deliberately not `grant_premium!`, which also posts to Slack.
  def set_premium!(premium)
    ensure_enrolled

    if premium
      participation.update!(premium: true, premium_granted_at: participation.premium_granted_at || Time.current)
      SeasonRewardGranter.new(participation).grant_for_level(participation.level)
    else
      participation.update!(premium: false, premium_granted_at: nil)
    end
    recalculate!
  end

  def grant_reward!(reward)
    ensure_enrolled
    SeasonRewardGranter.new(participation).grant_reward(reward)
    recalculate!
  end

  def recalculate!
    return unless participation

    SeasonProgressService.new(participation).recalculate
    participation.reload
  end

  # --- Community --------------------------------------------------------------

  # Runs the community job for this season now, rather than waiting for the
  # schedule, which never fires for a season that is not active yet.
  def self.run_community!(season)
    AggregateCommunityGoalsJob.perform_now(season.id)
  end

  # --- Bots -------------------------------------------------------------------

  # Other runners, so the leaderboard and the community bar have more than one
  # name on them. Each gets a random slice of the season.
  def self.add_bots!(season, count:, random: Random.new)
    count = count.to_i.clamp(1, MAX_BOTS)
    challenge_ids = season.season_challenges.pluck(:id)

    Array.new(count) do
      bot = create_bot(random)
      sandbox = new(season, bot)
      sandbox.generate_workouts!(count: random.rand(3..30), min_km: 2, max_km: 15, random: random)
      picked = challenge_ids.sample(random.rand(0..challenge_ids.size), random: random)
      sandbox.complete_challenges!(ids: picked) if picked.any?
      bot
    end
  end

  def self.remove_bots!
    bots.find_each.sum do |bot|
      bot.season_participations.includes(:season).each { |p| new(p.season, bot).reset! }
      AnalyticsEvent.where(user_id: bot.id).delete_all
      bot.user_badges.delete_all
      bot.workouts.delete_all
      bot.challenge_participations.delete_all
      bot.destroy!
      1
    end
  end

  def self.create_bot(random)
    tag = SecureRandom.hex(3)
    User.create!(
      first_name: BOT_FIRST_NAMES.sample(random: random),
      last_name: "Bot #{tag.upcase}",
      nickname: "bot_#{tag}",
      email: "bot-#{tag}@#{BOT_EMAIL_DOMAIN}",
      password: SecureRandom.hex(16)
    )
  end
  private_class_method :create_bot

  BOT_FIRST_NAMES = %w[Ana Bruno Carla Diego Elisa Felipe Gabi Hugo Iris João Kai Lara Mateus Nina Otto Paula Rafa Sofia Tiago Vera].freeze

  # --- Reset ------------------------------------------------------------------

  # Takes the user back to before they joined this season: their progress rows
  # go, what the season's rewards handed out is taken back, and every sandbox
  # workout in the season's dates is deleted. Real workouts are left alone.
  def reset!
    ApplicationRecord.transaction do
      revoke_reward_effects
      revoke_coins
      DailyChallengeAssignment.where(user: user, season: season).delete_all
      season.season_activities.where(user: user).delete_all
      remove_challenge_progress
      remove_sandbox_workouts
      participation&.destroy!
      @participation = nil
    end

    user.update_column(:lifetime_xp, user.season_participations.sum(:xp))
    Seasons::CommunityAggregator.refresh_season(season, force: true)
  end

  private

  def ensure_enrolled
    return if participation

    @participation = SeasonProgressService.ensure_participation(user, season)
    enroll_in_challenges
  end

  def enroll_in_challenges
    season.season_challenges.includes(:challenge).each do |season_challenge|
      ChallengeEnroller.call(user, season_challenge.challenge, season: season)
    end
  end

  def challenge_participations
    user.challenge_participations.where(season: season).includes(:challenge)
  end

  def recompute_challenges
    challenge_participations.each { |cp| RecomputeChallengeProgress.new(cp).call }
  end

  # An active season records these itself as the workouts finish challenges.
  # Any other season does not, so the sandbox does it — unclaimed, the way a
  # player would find them.
  def record_challenges_the_workouts_finished
    finished = challenge_participations.where.not(completed_at: nil).pluck(:challenge_id)
    season.season_challenges.where(challenge_id: finished).includes(:challenge).each do |season_challenge|
      record_challenge_completion(season_challenge, claim: false)
    end
  end

  # Mirrors RecomputeChallengeProgress#record_season_completion minus its gates.
  # Returns whether anything changed.
  def record_challenge_completion(season_challenge, claim:)
    completion = participation.season_challenge_completions.find_by(season_challenge: season_challenge)
    created = completion.nil?

    if created
      completion = participation.season_challenge_completions.create!(
        season_challenge: season_challenge, xp_awarded: season_challenge.xp_reward, completed_at: Time.current
      )
      credit_challenge_coins(season_challenge)
      SeasonActivity.create!(
        season: season, user: user,
        kind: season_challenge.special? ? "special_completed" : "challenge_completed",
        metadata: { challenge: season_challenge.challenge.display_title, xp: season_challenge.xp_reward, category: season_challenge.category }
      )
    end

    mark_challenge_participation_complete(season_challenge)
    claimed = claim && completion.claim!
    created || claimed
  end

  def credit_challenge_coins(season_challenge)
    Wallet.credit(
      user,
      amount: season_challenge.coin_reward,
      reason: "season_challenge",
      reason_key: "season_challenge:#{season_challenge.id}:#{participation.id}",
      metadata: { season_id: season.id, challenge: season_challenge.challenge.display_title }
    )
  end

  # So the challenge card reads as done, not only the season ledger.
  def mark_challenge_participation_complete(season_challenge)
    cp = ChallengeEnroller.call(user, season_challenge.challenge, season: season)
    cp&.update!(completed_at: Time.current) if cp && cp.completed_at.nil?
  end

  # XP the player has earned without the sandbox's help, before the season
  # multiplier — what the sandbox XP is added to.
  def earned_raw_xp
    breakdown = participation.xp_breakdown.to_h.except("multiplier", "sandbox")
    breakdown.values.sum(&:to_i)
  end

  # --- Dates ------------------------------------------------------------------

  def season_dates
    window = season.date_window
    raise Error, "The season needs a start and end date first." unless window

    window
  end

  # Defaults to the part of the season that has happened, so an active season
  # does not get workouts from next week. A season that has not started gets
  # its whole window.
  def workout_dates(from, to)
    window = season_dates
    last = season.current_date.between?(window.begin, window.end) ? season.current_date : window.end
    first = parse_date(from) || window.begin
    last = parse_date(to) || last

    dates = ([ first, window.begin ].max..[ last, window.end ].min).to_a
    raise Error, "Those dates are outside the season (#{window.begin} – #{window.end})." if dates.empty?

    dates
  end

  def daily_dates(days)
    window = season_dates
    days = days.to_i.clamp(1, MAX_DAILY_DAYS)
    today = season.current_date

    if today < window.begin
      (window.begin..[ window.begin + (days - 1), window.end ].min).to_a
    else
      last = [ today, window.end ].min
      ([ last - (days - 1), window.begin ].max..last).to_a
    end
  end

  def parse_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error
    raise Error, "#{value} is not a date."
  end

  # Shaped like Workout's own callbacks would leave it, with a known start time
  # so hour-based challenges and dailies can count it.
  def workout_row(date, sport, km, random)
    hour = random.rand(5..20)
    minute = random.rand(0..59)
    moving = (km * random.rand(300..420)).round # 5:00–7:00 per km
    started = Time.utc(date.year, date.month, date.day, hour, minute)

    {
      user_id: user.id,
      sport: sport,
      provider: WORKOUT_PROVIDER,
      external_id: "sandbox-#{SecureRandom.uuid}",
      distance_km: km,
      duration_minutes: (moving / 60.0).round,
      moving_time_seconds: moving,
      elapsed_time_seconds: moving + random.rand(0..120),
      elevation_gain_m: (km * random.rand(2.0..15.0)).round(1),
      calories: (km * random.rand(55..75)).round,
      workout_date: date,
      started_at: started,
      started_at_local: started,
      start_time_known: true,
      start_minute_of_day: (hour * 60) + minute
    }
  end

  # --- Reset helpers ----------------------------------------------------------

  def granted_rewards
    return SeasonReward.none unless participation

    SeasonReward.where(id: participation.season_reward_grants.select(:season_reward_id))
  end

  # Undoes what SeasonRewardGranter#apply did. Coins go with the rest of the
  # season's coins in #revoke_coins.
  def revoke_reward_effects
    granted_rewards.each do |reward|
      case reward.reward_type
      when "title"    then user.remove_title(reward.reward_key)
      when "theme"    then user.update_column(:unlocked_themes, user.unlocked_themes - [ reward.reward_key.to_s ])
      when "badge"    then user.user_badges.joins(:badge).where(badges: { name: reward.name.presence || "Season: #{reward.reward_key}" }).delete_all
      when "cosmetic" then revoke_cosmetic(reward.reward_key)
      when "xp_boost" then user.user_xp_boosts.where(source_key: "season_reward:#{reward.id}").delete_all
      end
    end
  end

  def revoke_cosmetic(key)
    cosmetic = Cosmetic.find_by(key: key)
    return unless cosmetic

    user.user_cosmetics.where(cosmetic: cosmetic, source: "season_reward").delete_all
    user.unequip_cosmetic!(cosmetic.kind) if user.equipped[cosmetic.kind] == cosmetic.key
  end

  def revoke_coins
    user.coin_transactions.where("metadata ->> 'season_id' = ?", season.id.to_s).delete_all
    Wallet.rebuild_balance(user)
  end

  def remove_challenge_progress
    participations = user.challenge_participations.where(season: season)
    Workout.where(challenge_participation_id: participations.select(:id)).update_all(challenge_participation_id: nil)

    # Completion badges only go when no other run at the same challenge earned one.
    challenge_ids = participations.where.not(completed_at: nil).pluck(:challenge_id)
    still_earned = user.challenge_participations.where(challenge_id: challenge_ids).where.not(completed_at: nil)
                       .where("season_id IS NULL OR season_id <> ?", season.id).pluck(:challenge_id)
    user.user_badges.where(challenge_id: challenge_ids - still_earned).delete_all

    participations.delete_all
  end

  def remove_sandbox_workouts
    user.workouts.where(provider: WORKOUT_PROVIDER, workout_date: season_dates).delete_all
  rescue Error
    nil # an undated season has no sandbox workouts to find
  end
end
