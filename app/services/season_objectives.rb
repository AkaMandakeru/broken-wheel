# frozen_string_literal: true

# Evaluates action-based season objectives (join a club, club workouts, …) and
# records durable completions when their target is met.
module SeasonObjectives
  module_function

  # Enqueue a recalc for every active season that has an objective of one of the
  # given kinds — used by club/workout triggers so we only touch relevant seasons.
  def enqueue_for(user, kinds:)
    season_ids = SeasonObjective.where(kind: kinds).distinct.pluck(:season_id)
    Season.active.where(id: season_ids).find_each do |season|
      SeasonRecalcJob.perform_later(user.id, season.id)
    end
  end

  # Record any newly-met objective completions for this participation. Durable
  # (one row per participation+objective), so XP never regresses.
  def evaluate(participation)
    season = participation.season
    user = participation.user

    season.season_objectives.find_each do |objective|
      next if participation.season_objective_completions.exists?(season_objective: objective)
      next unless progress(objective, user, season) >= objective.target

      begin
        participation.season_objective_completions.create!(
          season_objective: objective,
          xp_awarded: objective.xp_reward,
          completed_at: Time.current
        )
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        next # already recorded by a concurrent recalc
      end

      SeasonActivity.create!(
        season: season,
        user: user,
        kind: "objective_completed",
        metadata: { objective: I18n.t("seasons.objectives.kinds.#{objective.kind}", default: objective.kind), xp: objective.xp_reward }
      )
    end
  end

  def progress(objective, user, season)
    case objective.kind
    when "join_club"    then user.club_memberships.exists? ? 1 : 0
    when "club_workout" then club_workouts_count(user, season)
    else 0
    end
  end

  # Workouts logged within the season window while the user belongs to a club.
  def club_workouts_count(user, season)
    return 0 unless user.club_memberships.exists?

    scope = user.workouts
    scope = scope.where(workout_date: season.starts_at.to_date..season.ends_at.to_date) if season.window
    scope.count
  end
end
