# frozen_string_literal: true

module Accounts
  # Deleting a player's account, from the web (Devise's "Cancel my account")
  # or the app (DELETE /api/v1/me — App Store guideline 5.1.1(v)).
  #
  # `user.destroy` alone cannot do it: most tables point at users with a plain
  # foreign key, and some of those rows belong to *other* players (clubs the
  # player founded, invitations they sent, reports they resolved). So this
  # removes what was the player's own, repoints or clears what is shared, and
  # only then destroys the user — all in one transaction, so a failure halfway
  # leaves the account exactly as it was.
  #
  # Order matters where rows point at each other: posts and event entries point
  # at workouts, and workouts point at challenge participations.
  class Deletion
    def self.call(user) = new(user).call

    # The app's path: the player is signed out and locked out at once, and the
    # rows go in the background (Accounts::DeletionJob). Locking keeps them
    # from signing back in to an account that is about to disappear.
    def self.request(user)
      user.lock_access!(send_instructions: false)
      sign_out_everywhere(user)
      DeletionJob.perform_later(user.id)
    end

    def self.sign_out_everywhere(user)
      user.api_sessions.where(revoked_at: nil)
          .update_all(revoked_at: Time.current, revoked_reason: "account_deleted", updated_at: Time.current)
    end

    def initialize(user)
      @user = user
    end

    def call
      User.transaction do
        sign_out_everywhere
        detach_from_other_players
        leave_clubs
        hand_over_clubs
        remove_activity
        @user.destroy!
      end
    end

    private

    attr_reader :user

    # Revoked rather than deleted first, so a token presented mid-deletion
    # already fails; destroy removes the rows afterwards.
    def sign_out_everywhere = self.class.sign_out_everywhere(user)

    def detach_from_other_players
      ChallengeParticipation.where(invited_by_id: user.id).update_all(invited_by_id: nil)
      UserBlock.where(blocked_id: user.id).delete_all

      # A report the team already closed stays as moderation history, just no
      # longer naming the player. An open one about the player or what they
      # posted has nothing left to review — except a club, which outlives them.
      ContentReport.where(resolved_by_id: user.id).update_all(resolved_by_id: nil)
      about_user = ContentReport.where(reported_user_id: user.id)
                                .or(ContentReport.where(reportable_type: "User", reportable_id: user.id))
      about_user.open.where.not(reportable_type: "Club").delete_all
      about_user.update_all(reported_user_id: nil)
    end

    # Leaving the way a member does, so member_count drops as it would.
    def leave_clubs
      user.clubs.distinct.each { |club| Clubs::Membership.new(club, user).leave }
      # club_memberships has no unique index; a duplicate row must not survive.
      ClubMembership.where(user_id: user.id).delete_all
    end

    # created_by_id cannot be null: a club the player founded passes to its
    # longest-standing member, and a club with nobody left in it goes too.
    def hand_over_clubs
      Club.where(created_by_id: user.id).find_each do |club|
        successor = club.club_memberships.order(:created_at, :id).first
        if successor
          club.update!(created_by_id: successor.user_id)
          successor.update!(role: "admin")
        else
          ContentReport.where(reportable: club).delete_all
          club.destroy!
        end
      end
    end

    def remove_activity
      # Comments on other people's posts; the ones on the player's own posts go
      # with the posts.
      TimelinePostComment.where(user_id: user.id).delete_all
      user.timeline_posts.destroy_all
      # destroy, not delete: it keeps each event's participation counter right.
      user.event_participations.destroy_all

      workout_ids = user.workouts.ids
      TimelinePost.where(workout_id: workout_ids).update_all(workout_id: nil)
      EventParticipation.where(workout_id: workout_ids).update_all(workout_id: nil)
      Workout.where(user_id: user.id).delete_all

      participation_ids = user.challenge_participations.ids
      Workout.where(challenge_participation_id: participation_ids).update_all(challenge_participation_id: nil)
      ChallengeParticipation.where(user_id: user.id).delete_all

      UserBadge.where(user_id: user.id).delete_all
      AnalyticsEvent.where(user_id: user.id).delete_all
    end
  end
end
