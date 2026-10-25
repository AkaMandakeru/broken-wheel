# frozen_string_literal: true

module Challenges
  # Which season a standalone challenge page is read in, and the viewer's
  # progress and the ranking in that same season. Shared by the web's
  # ChallengesController and Api::V1::ChallengesController.
  #
  #   context = Challenges::Context.new(challenge, user: current_user)
  #   context.season          # nil for a challenge outside any active season
  #   context.participation   # the viewer's row in that context
  #   context.ranking
  class Context
    # The challenge list, newest first, optionally narrowed to one type.
    def self.listing(type: nil)
      Challenge.where(status: "active").of_type(type).order(starts_at: :desc)
    end

    # { challenge_id => participation } for a list, preferring each challenge's
    # season row so the list matches what the challenge page will show.
    def self.participation_index(user, challenges)
      return {} unless user

      user.challenge_participations
          .where(challenge_id: challenges.map(&:id))
          .order(Arel.sql("season_id IS NULL"))
          .index_by(&:challenge_id)
    end

    # The timeline is open to anyone who joined the challenge in any season.
    def self.participant?(user, challenge)
      user.present? && user.challenge_participations.exists?(challenge_id: challenge.id)
    end

    attr_reader :challenge, :user

    def initialize(challenge, user: nil)
      @challenge = challenge
      @user = user
    end

    # The active season this challenge belongs to, if any. A challenge can run
    # in several seasons; progress and ranking must come from the same one or
    # the board would mix scores from different months.
    def season
      return @season if defined?(@season)

      @season = Season.active
                      .joins(:season_challenges)
                      .where(season_challenges: { challenge_id: challenge.id })
                      .by_recent
                      .first
    end

    def participation
      return @participation if defined?(@participation)

      @participation = user&.challenge_participations&.for_context(season)&.find_by(challenge_id: challenge.id)
    end

    def joined? = participation.present?

    # Joins the viewer in this context, the way the "join" button does on
    # either client. Nil when they had already joined.
    def join!
      return nil if joined?

      @participation = ChallengeEnroller.call(user, challenge, season: season)
      Analytics.track(user: user, event: "challenge_joined",
                      properties: { challenge_id: challenge.id, challenge_type: challenge.challenge_type, sport: challenge.sport })
      @participation
    end

    def ranking
      @ranking ||= challenge.challenge_participations.for_context(season).includes(:user).order(progress_value: :desc)
    end
  end
end
