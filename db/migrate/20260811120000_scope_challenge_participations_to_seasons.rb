# frozen_string_literal: true

# Progress on a challenge was global per (user, challenge). Attaching the same
# challenge to a second season therefore carried the first season's progress
# straight over — a challenge could show as already finished in a brand-new
# season, and (worse) never award that season's XP, because completion only
# fires on the transition from unfinished to finished.
#
# Participation is now scoped to a season. `season_id` is null for standalone
# challenges joined outside any season, which keeps /challenges working as before.
class ScopeChallengeParticipationsToSeasons < ActiveRecord::Migration[8.1]
  def up
    add_column :challenge_participations, :season_id, :bigint
    add_foreign_key :challenge_participations, :seasons
    add_index :challenge_participations, :season_id

    # Existing progress was earned in whichever season the challenge first ran
    # in, so each row is assigned to the earliest season containing it. Leaving
    # a shared challenge unassigned would be worse than picking: its progress
    # would vanish from every season at once.
    execute <<~SQL.squish
      UPDATE challenge_participations cp
      SET season_id = sub.season_id
      FROM (
        SELECT DISTINCT ON (sc.challenge_id) sc.challenge_id, sc.season_id
        FROM season_challenges sc
        JOIN seasons s ON s.id = sc.season_id
        ORDER BY sc.challenge_id, s.starts_at ASC NULLS LAST, sc.season_id ASC
      ) sub
      WHERE cp.challenge_id = sub.challenge_id
    SQL

    # This table never had a uniqueness constraint, so duplicate (user,
    # challenge) rows could already exist — ChallengeEnroller's find-then-create
    # had nothing but timing protecting it. Collapse them onto the furthest
    # progressed row before the index goes on, moving any attributed workouts
    # across so nothing loses its link.
    execute <<~SQL.squish
      UPDATE workouts w
      SET challenge_participation_id = keep.id
      FROM challenge_participations dup
      JOIN (
        SELECT DISTINCT ON (user_id, challenge_id, season_id) id, user_id, challenge_id, season_id
        FROM challenge_participations
        ORDER BY user_id, challenge_id, season_id, progress_value DESC NULLS LAST, id ASC
      ) keep
        ON keep.user_id = dup.user_id
       AND keep.challenge_id = dup.challenge_id
       AND keep.season_id IS NOT DISTINCT FROM dup.season_id
      WHERE w.challenge_participation_id = dup.id
        AND dup.id <> keep.id
    SQL

    execute <<~SQL.squish
      DELETE FROM challenge_participations cp
      WHERE cp.id NOT IN (
        SELECT DISTINCT ON (user_id, challenge_id, season_id) id
        FROM challenge_participations
        ORDER BY user_id, challenge_id, season_id, progress_value DESC NULLS LAST, id ASC
      )
    SQL

    # Postgres treats NULLs as distinct, so the two cases need separate partial
    # indexes to be genuinely unique.
    add_index :challenge_participations, [ :user_id, :challenge_id, :season_id ],
              unique: true, where: "season_id IS NOT NULL",
              name: "idx_challenge_participations_user_challenge_season"
    add_index :challenge_participations, [ :user_id, :challenge_id ],
              unique: true, where: "season_id IS NULL",
              name: "idx_challenge_participations_user_challenge_standalone"
  end

  def down
    remove_index :challenge_participations, name: "idx_challenge_participations_user_challenge_season"
    remove_index :challenge_participations, name: "idx_challenge_participations_user_challenge_standalone"
    remove_foreign_key :challenge_participations, :seasons
    remove_column :challenge_participations, :season_id
  end
end
