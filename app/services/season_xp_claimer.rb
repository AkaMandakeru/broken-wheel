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

    Result.new(
      claimed: claimed.size,
      xp: xp,
      level_before: level_before,
      level_after: @participation.reload.level,
      participation: @participation
    )
  end

  private

  # Guards against claiming someone else's completion by id.
  def belongs_to_participation?(completion)
    completion.season_participation_id == @participation.id
  end
end
