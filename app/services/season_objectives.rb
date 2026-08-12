# frozen_string_literal: true

# Evaluates season objectives — the club/action goals and the five Legacy
# Missions — and records durable completions when their target is met.
#
# Progress resolves through ChallengeMetrics, so adding an objective type is a
# blueprint entry rather than a new branch here.
module SeasonObjectives
  module_function

  # Enqueue a recalc for every active season that has an objective of one of the
  # given kinds — used by club/workout triggers so we only touch relevant seasons.
  def enqueue_for(user, kinds:)
    season_ids = SeasonObjective.where(kind: kinds).distinct.pluck(:season_id)
    Season.active.where(id: season_ids).find_each do |season|
      SeasonRecalcJob.enqueue_debounced(user.id, season.id)
    end
  end

  # Record any newly-met objective completions for this participation. Durable
  # (one row per participation+objective), so XP never regresses.
  def evaluate(participation, context: nil)
    season = participation.season
    user = participation.user
    context ||= ChallengeMetrics::Context.new(
      user: user, window: season.date_window, season: season, participation: participation
    )

    completed_ids = participation.season_objective_completions.pluck(:season_objective_id).to_set

    season.season_objectives.each do |objective|
      next if completed_ids.include?(objective.id)
      next unless satisfied?(objective, context)

      record_completion(participation, objective, season, user)
    end
  end

  def satisfied?(objective, context)
    value = progress(objective, context)
    ChallengeMetrics.satisfied?(objective.metric_key, value, objective.target)
  end

  def progress(objective, context)
    ChallengeMetrics.call(objective.metric_key, context.rescope(options: objective.options))
  end

  # Value for display, without recording anything.
  def progress_for(participation, objective, context: nil)
    context ||= ChallengeMetrics::Context.new(
      user: participation.user,
      window: participation.season.date_window,
      season: participation.season,
      participation: participation
    )
    progress(objective, context)
  end

  def record_completion(participation, objective, season, user)
    participation.season_objective_completions.create!(
      season_objective: objective,
      xp_awarded: objective.xp_reward,
      completed_at: Time.current
    )

    credit_coins(user, participation, objective, season)

    SeasonActivity.create!(
      season: season,
      user: user,
      kind: objective.legacy? ? "legacy_mission_completed" : "objective_completed",
      metadata: { objective: objective.display_name, xp: objective.xp_reward, track: objective.track }
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil # already recorded by a concurrent recalc
  end

  def credit_coins(user, participation, objective, season)
    return if objective.coin_reward.to_i.zero?

    Wallet.credit(
      user,
      amount: objective.coin_reward,
      reason: "season_objective",
      reason_key: "season_objective:#{objective.id}:#{participation.id}",
      metadata: { season_id: season.id, objective: objective.display_name }
    )
  end
end
