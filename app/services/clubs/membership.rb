# frozen_string_literal: true

module Clubs
  # Joining, leaving and founding a club, for the web's ClubsController and
  # Api::V1::ClubsController alike. Memberships are created through the
  # association so ClubMembership's callbacks (season objectives) still fire.
  #
  # club_memberships has no unique index on (club_id, user_id), so a double tap
  # is kept from creating two rows by locking the club row: the second join
  # waits for the first to commit, then sees the membership.
  class Membership
    # Saves the club and makes its founder the first (admin) member. False when
    # the club is invalid.
    def self.create_with_founder(club, founder)
      club.created_by = founder
      Club.transaction do
        raise ActiveRecord::Rollback unless club.save

        club.club_memberships.create!(user: founder, role: "admin")
        club.increment!(:member_count)
      end
      club.persisted?
    end

    attr_reader :club, :user

    def initialize(club, user)
      @club = club
      @user = user
    end

    def current
      user.club_memberships.find_by(club: club)
    end

    # The new membership, or nil when the user was already a member.
    def join
      membership = club.with_lock do
        next nil if user.club_memberships.exists?(club: club)

        club.club_memberships.create!(user: user, role: "member").tap { club.increment!(:member_count) }
      end
      return nil unless membership

      Analytics.track(user: user, event: "club_joined", properties: { club_id: club.id, club_name: club.name, sport: club.sport })
      membership
    end

    # False when the user wasn't a member.
    def leave
      club.with_lock do
        membership = user.club_memberships.find_by(club: club)
        next false unless membership

        membership.destroy!
        club.decrement!(:member_count)
        true
      end
    end
  end
end
