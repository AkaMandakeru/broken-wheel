# frozen_string_literal: true

# The six season rankings. Separate boards exist so a beginner who will never
# top the distance table can still lead on streak or activity count.
#
# Every board reads denormalised columns on season_participations, written
# during recalculation — no per-request aggregation over workouts.
class SeasonLeaderboard
  CACHE_TTL = 5.minutes

  BOARDS = {
    xp:         { column: :xp,                  direction: :desc },
    distance:   { column: :total_distance_km,   direction: :desc },
    activities: { column: :activities_count,    direction: :desc },
    streak:     { column: :longest_streak_days, direction: :desc },
    fastest_5k: { column: :best_5k_seconds,     direction: :asc  },
    elevation:  { column: :elevation_gain_m,    direction: :desc }
  }.freeze

  def self.boards = BOARDS.keys

  def initialize(season, board: :xp)
    @season = season
    @board = BOARDS.key?(board.to_sym) ? board.to_sym : :xp
  end

  attr_reader :board

  def config
    BOARDS.fetch(@board)
  end

  def top(limit = 10)
    Rails.cache.fetch(cache_key(limit), expires_in: CACHE_TTL) { query.limit(limit).to_a }
  end

  # The signed-in user's standing, so someone outside the top ten still sees
  # where they are.
  def position_for(participation)
    return nil if participation.nil?

    value = participation.public_send(config[:column])
    return nil if value.nil?

    better = if config[:direction] == :asc
      base_scope.where.not(config[:column] => nil).where(config[:column] => ...value)
    else
      base_scope.where(config[:column] => (value + 1)..)
    end

    better.count + 1
  end

  def value_for(participation)
    participation&.public_send(config[:column])
  end

  private

  def base_scope
    @season.season_participations
  end

  # Fastest-5k is ascending, and a NULL there means "never ran 5 km" — those
  # rows must fall off the board rather than sort to the front.
  def query
    scope = base_scope.includes(:user)
    column = config[:column]

    if config[:direction] == :asc
      scope.where.not(column => nil).order(column => :asc, updated_at: :asc)
    else
      scope.where(column => 1..).order(column => :desc, updated_at: :asc)
    end
  end

  def cache_key(limit)
    stamp = base_scope.maximum(:updated_at)&.to_i
    "season_leaderboard/#{@season.id}/#{@board}/#{limit}/#{stamp}"
  end
end
