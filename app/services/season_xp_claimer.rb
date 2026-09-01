# frozen_string_literal: true

# Collects the XP waiting on finished challenges.
#
# The claim itself is a stamp on the completion row; the XP total is then
# recomputed from the ledger as usual, so claiming stays consistent with the
# rest of the season engine — nothing is incremented in place, and re-running a
# recalculation can never double-pay or lose a claim.
class SeasonXpClaimer
  Result = Struct.new(:claimed, :xp, :level_before, :level_after, :participation, keyword_init: true) do
    def any? = claimed.positive?
    def levelled_up? = level_after > level_before
  end

  def initialize(participation)
    @participation = participation
  end

  # Claims one completion, or every pending one when `completion` is nil.
  def call(completion: nil)
    level_before = @participation.level
    targets = completion ? [ completion ] : @participation.unclaimed_completions.to_a

    claimed = targets.select { |target| belongs_to_participation?(target) && target.claim! }
    xp = claimed.sum(&:xp_awarded)

    SeasonProgressService.new(@participation).recalculate if claimed.any?

    result = Result.new(
      claimed: claimed.size,
      xp: xp,
      level_before: level_before,
      level_after: @participation.reload.level,
      participation: @participation
    )

    track(result) if result.any?
    result
  end

  private

  # The gap between completing a challenge and claiming its XP is the number
  # that says whether the claim mechanic is being noticed at all, so only real
  # claims are recorded — a no-op claim would flatten that signal.
  def track(result)
    season = @participation.season

    SeasonAnalytics.track(
      user: @participation.user, event: "season_xp_claimed", season: season,
      claimed_count: result.claimed, xp: result.xp,
      levelled_up: result.levelled_up?, level: result.level_after
    )
  end

  # Guards against claiming someone else's completion by id.
  def belongs_to_participation?(completion)
    completion.season_participation_id == @participation.id
  end
end
