# frozen_string_literal: true

# The locker: what a player owns, what they do not, and which one is on their
# profile. Equipping is the only write, and User#equip_cosmetic! is what makes
# it safe — it refuses anything the user does not own.
class AppearancesController < ApplicationController
  before_action :authenticate_user!

  KINDS = Cosmetic::PICTURE_KINDS

  def show
    @kind = requested_kind
    @owned = current_user.owned_cosmetics(@kind).to_a
    @locked = current_user.unowned_cosmetics(@kind).to_a
    @equipped_key = current_user.equipped[@kind]
    @claimable = SeasonRewardClaimer.available_for(current_user, kind: @kind)
    # A claimable one is not "locked" — it is waiting to be taken, so it gets its
    # own section rather than a padlock the player could do nothing about.
    claimable_keys = @claimable.map { |cosmetic, _| cosmetic.key }.to_set
    @locked.reject! { |cosmetic| claimable_keys.include?(cosmetic.key) }
    # Lets a locked card say "Season 8 · Level 12" rather than just greying out.
    @unlock_hints = SeasonReward.cosmetic_unlocks_for(@locked.map(&:key))
  end

  # The player taking a reward the season has put on offer.
  def claim
    kind = requested_kind
    result = SeasonRewardClaimer.new(current_user).call(params[:key])

    case result.status
    when :claimed then back_to_locker(kind, notice: t("appearances.flashes.claimed"))
    when :already_owned then back_to_locker(kind, notice: t("appearances.flashes.already_owned"))
    else back_to_locker(kind, alert: t("appearances.flashes.unavailable"))
    end
  end

  def update
    kind = requested_kind
    key = params[:key].to_s

    if key.blank?
      current_user.unequip_cosmetic!(kind)
      back_to_locker(kind, notice: t("appearances.flashes.removed"))
    elsif current_user.equip_cosmetic!(kind, key)
      back_to_locker(kind, notice: t("appearances.flashes.equipped"))
    else
      # Not owned, or owned but not renderable. Both are "you cannot wear this",
      # and saying which would tell an attacker what exists.
      back_to_locker(kind, alert: t("appearances.flashes.unavailable"))
    end
  end

  private

  def back_to_locker(kind, **flash)
    redirect_to profile_appearance_path(kind: kind), **flash
  end

  def requested_kind
    KINDS.include?(params[:kind]) ? params[:kind] : KINDS.first
  end
end
