# frozen_string_literal: true

# The locker: what a player owns, what they do not, and which one is on their
# profile. Equipping is the only write, and User#equip_cosmetic! is what makes
# it safe — it refuses anything the user does not own.
class AppearancesController < ApplicationController
  before_action :authenticate_user!

  KINDS = Locker::Catalogue::KINDS

  def show
    @kind = requested_kind
    catalogue = Locker::Catalogue.new(current_user, kind: @kind)
    @owned = catalogue.owned
    @locked = catalogue.locked
    @equipped_key = catalogue.equipped_key
    @claimable = catalogue.claimable
    @unlock_hints = catalogue.unlock_hints
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
