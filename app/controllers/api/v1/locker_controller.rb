# frozen_string_literal: true

module Api
  module V1
    # The locker, as on the web's appearance page: what the player owns, what a
    # season is offering, and what is still locked. Equipping goes through
    # User#equip_cosmetic!, which refuses anything not owned or not renderable.
    class LockerController < BaseController
      idempotent only: :claim

      before_action :set_kind, only: [ :update, :destroy ]

      def index
        kind = params.fetch(:kind, Locker::Catalogue::KINDS.first)
        return render_error(:bad_request, "invalid_kind") unless Locker::Catalogue.kind?(kind)

        render_locker kind
      end

      def update
        # Not owned, or owned but not renderable. Both are "you cannot wear
        # this", and saying which would tell an attacker what exists.
        return render_error(:unprocessable_content, "cosmetic_unavailable") unless current_user.equip_cosmetic!(@kind, params.expect(:key))

        track_event "api.locker.equipped", kind: @kind, key: params[:key]
        render_locker @kind
      end

      def destroy
        current_user.unequip_cosmetic!(@kind)
        track_event "api.locker.unequipped", kind: @kind
        render_locker @kind
      end

      # The player taking a reward the season has put on offer. The offer is
      # looked up again by SeasonRewardClaimer, never trusted from the client.
      def claim
        key = params.expect(:key).to_s
        result = SeasonRewardClaimer.new(current_user).call(key)
        return render_error(:unprocessable_content, "cosmetic_unavailable") if result.status == :unavailable

        track_event "api.locker.claimed", key: key if result.claimed?
        cosmetic = current_user.cosmetics.with_artwork.find_by!(key: key)
        render_data({ status: result.status.to_s, cosmetic: CosmeticResource.new(cosmetic).serializable_hash },
                    status: result.claimed? ? :created : :ok)
      end

      private

      def set_kind
        @kind = params[:kind].to_s
        raise ActiveRecord::RecordNotFound unless Locker::Catalogue.kind?(@kind)
      end

      def render_locker(kind)
        render_resource LockerResource, Locker::Catalogue.new(current_user, kind: kind)
      end
    end
  end
end
