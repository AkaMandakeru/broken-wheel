# frozen_string_literal: true

module Seasons
  # Everything the season page shows, one section at a time: the web's
  # SeasonsController#show renders it all, and each mobile endpoint
  # (Api::V1::Seasons::*) asks for just its own section. Every section is
  # memoised, so a section is only queried when something reads it.
  #
  #   dashboard = Seasons::Dashboard.new(season, user: current_user, board: params[:board])
  #   dashboard.enroll!            # viewing an active season joins it
  #   dashboard.weekly_challenges
  class Dashboard
    LEADERBOARD_SIZE = 10
    ACTIVITY_LIMIT = 15

    # Admins keep the whole history, so the admin panel's "view public" link
    # still resolves for a season players can no longer open.
    def self.season_scope(user)
      user&.admin? ? Season.all : Season.browsable
    end

    attr_reader :season, :user

    def initialize(season, user: nil, board: nil)
      @season = season
      @user = user
      @board = board
    end

    # Lazy auto-enrollment: viewing an active season creates the participation
    # so progress and rank show immediately (starting at zero).
    def enroll!
      return participation unless user && season.active?

      @participation = SeasonProgressService.ensure_participation(user, season)
    end

    def participation
      return @participation if defined?(@participation)

      @participation = user&.season_participations&.find_by(season_id: season.id)
    end

    def unclaimed_completions
      @unclaimed_completions ||= participation&.unclaimed_completions.to_a
    end

    # --- Challenges -----------------------------------------------------------

    # Every challenge is on the board. Special ones used to be withheld until a
    # player stumbled into completing one; they are listed like the rest now, so
    # the progress bar is something to aim at rather than a reveal.
    def challenges
      @challenges ||= season.season_challenges
                            .includes(challenge: [ :challenge_requirements, { image_attachment: :blob } ]).to_a
    end

    def challenges_by_category
      @challenges_by_category ||= challenges.group_by(&:category)
    end

    def weekly_challenges
      @weekly_challenges ||= (challenges_by_category["weekly"] || []).sort_by { |sc| sc.week_index.to_i }
    end

    def special_challenges
      challenges_by_category["special"] || []
    end

    # { challenge_id => participation } for the user, for the season's challenges.
    def challenge_progress
      @challenge_progress ||= if user
        rows = user.challenge_participations
                   .where(challenge_id: challenges.map(&:challenge_id), season_id: season.id).to_a
        # Each row's requirement_status reads its challenge's requirements;
        # hand it the challenges already loaded above instead of one query each.
        ActiveRecord::Associations::Preloader.new(
          records: rows, associations: :challenge, available_records: challenges.map(&:challenge)
        ).call
        rows.index_by(&:challenge_id)
      else
        {}
      end
    end

    # When the player's challenge progress last moved — part of the HTTP cache
    # key for anything that shows it.
    def challenge_progress_updated_at
      return nil unless user

      user.challenge_participations.where(season_id: season.id).maximum(:updated_at)
    end

    # The soonest special event that hasn't finished yet — today's counts, since
    # it can still be done. An event is a special with its own dates (Children's
    # Day, Halloween), the ones SpecialEventReminder emails about; a special
    # that runs all season is just a harder challenge. Nil when none is left.
    def next_special_event
      return @next_special_event if defined?(@next_special_event)

      @next_special_event = special_challenges
                            .select { |sc| sc.starts_at.present? && !sc.window_ended? }
                            .min_by { |sc| [ sc.event_date, sc.position ] }
    end

    # --- Objectives -----------------------------------------------------------

    def objectives
      @objectives ||= season.season_objectives.standard.to_a
    end

    def legacy_missions
      @legacy_missions ||= season.season_objectives.legacy.to_a
    end

    def completed_objective_ids
      @completed_objective_ids ||= participation&.season_objective_completions&.pluck(:season_objective_id) || []
    end

    def legacy_completed_count
      legacy_missions.count { |mission| completed_objective_ids.include?(mission.id) }
    end

    # --- Dailies --------------------------------------------------------------

    # Assigning here as well as in the nightly job means someone who joins
    # mid-day sees today's set immediately. The draw is deterministic, so both
    # paths produce the same three.
    def daily_assignments
      @daily_assignments ||= if participation && season.active?
        DailyChallenges::Assigner.call(user, season)
      else
        []
      end
    end

    # Live value for each of today's dailies, so the bars move before the next
    # recalculation lands. One context is built and shared, so the whole set
    # costs a single read of the user's workouts.
    def daily_progress
      @daily_progress ||= begin
        assignments = daily_assignments
        if assignments.empty?
          {}
        else
          context = ChallengeMetrics::Context.new(
            user: user, window: nil, season: season, participation: participation
          )
          assignments.index_with { |assignment| assignment.progress_in(context) }
        end
      end
    end

    # --- Rewards --------------------------------------------------------------

    def level_rewards
      @level_rewards ||= season.season_rewards.where(unlock_kind: "level").order(:level, :track).to_a
    end

    def rewards_by_level
      @rewards_by_level ||= level_rewards.group_by(&:level)
    end

    def bonus_rewards
      @bonus_rewards ||= season.season_rewards.where.not(unlock_kind: "level").order(:unlock_kind, :unlock_value).to_a
    end

    def granted_reward_ids
      @granted_reward_ids ||= participation&.granted_reward_ids || []
    end

    # --- Leaderboard ----------------------------------------------------------

    def board
      leaderboard.board
    end

    def leaderboard
      @leaderboard ||= SeasonLeaderboard.new(season, board: @board.presence || :xp)
    end

    def leaderboard_rows
      @leaderboard_rows ||= leaderboard.top(LEADERBOARD_SIZE)
    end

    def my_position
      return @my_position if defined?(@my_position)

      @my_position = leaderboard.position_for(participation)
    end

    # --- Community and feed ---------------------------------------------------

    def community_goal
      return @community_goal if defined?(@community_goal)

      @community_goal = season.season_community_goals.includes(season_community_milestones: :season_reward).first
    end

    # Newest first, ending on id so a cursor over it stays stable.
    def activities_scope
      season.season_activities.includes(:user).order(created_at: :desc, id: :desc)
    end

    def recent_activities
      @recent_activities ||= activities_scope.limit(ACTIVITY_LIMIT).to_a
    end
  end
end
