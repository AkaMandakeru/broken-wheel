# frozen_string_literal: true

# Walks every participant in a season, a batch at a time, re-enqueueing the job
# for the next batch instead of looping.
#
# Chaining rather than looping keeps a single job short no matter how large the
# community grows. The off-by-one on the resume cursor is the easy thing to get
# wrong — it lives here once rather than in each payout job.
module GrantsToSeasonParticipants
  extend ActiveSupport::Concern

  BATCH_SIZE = 500

  private

  # `resume_args` are the job's own leading arguments; the cursor is appended, so
  # the job's `perform` must accept `after_id` last.
  def each_participant_batch(season, after_id, *resume_args)
    scope = season.season_participations.includes(:user).order(:id)
    scope = scope.where(id: after_id..) if after_id

    batch = scope.limit(BATCH_SIZE).to_a
    return if batch.empty?

    batch.each { |participation| yield participation }

    next_id = season.season_participations.where(id: (batch.last.id + 1)..).order(:id).limit(1).pick(:id)
    self.class.perform_later(*resume_args, next_id) if next_id
  end
end
