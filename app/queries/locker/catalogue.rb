# frozen_string_literal: true

module Locker
  # One kind of a player's locker: what they own, what is waiting to be claimed,
  # and what is still locked (with where to earn it). Read by the appearance
  # page and GET /api/v1/me/locker.
  #
  #   catalogue = Locker::Catalogue.new(user, kind: "frame")
  #   catalogue.owned        # => [Cosmetic, ...]
  #   catalogue.claimable    # => [[Cosmetic, SeasonReward], ...]
  #   catalogue.locked       # => [Cosmetic, ...]
  #   catalogue.unlock_hints # => { "cosmetic_key" => SeasonReward }
  class Catalogue
    # Only kinds a player picks from a grid. They are the same kinds
    # SeasonRewardClaimer offers, so anything listed as claimable can be claimed.
    KINDS = Cosmetic::PICTURE_KINDS

    attr_reader :user, :kind

    def self.kind?(kind) = KINDS.include?(kind.to_s)

    def initialize(user, kind:)
      @user = user
      @kind = kind.to_s
    end

    def owned
      @owned ||= user.owned_cosmetics(kind).to_a
    end

    def equipped_key
      user.equipped[kind]
    end

    def claimable
      @claimable ||= SeasonRewardClaimer.available_for(user, kind: kind)
    end

    # A claimable one is not "locked" — it is waiting to be taken, so it gets
    # its own section rather than a padlock the player could do nothing about.
    def locked
      @locked ||= begin
        claimable_keys = claimable.map { |cosmetic, _| cosmetic.key }.to_set
        user.unowned_cosmetics(kind).to_a.reject { |cosmetic| claimable_keys.include?(cosmetic.key) }
      end
    end

    # Lets a locked card say "Season 8 · Level 12" rather than just greying out.
    def unlock_hints
      @unlock_hints ||= SeasonReward.cosmetic_unlocks_for(locked.map(&:key))
    end
  end
end
