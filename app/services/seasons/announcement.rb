# frozen_string_literal: true

module Seasons
  # The "a new season has started" banner a signed-in user should see, if any.
  #
  # Push only reaches players who granted notification permission — a small
  # fraction — so this is what actually tells everyone else. It shows on any page
  # until dismissed, then stays gone.
  class Announcement
    # After a week it isn't news any more, and the season page speaks for itself.
    VISIBLE_FOR = 7.days

    def self.for(user)
      new(user).season
    end

    def initialize(user)
      @user = user
    end

    def season
      return nil if @user.nil?

      candidate = Season.active
                        .where.not(announced_at: nil)
                        .where(announced_at: VISIBLE_FOR.ago..)
                        .by_recent
                        .first
      return nil if candidate.nil?
      return nil if @user.dismissed_season_announcement?(candidate.id)

      candidate
    end
  end
end
