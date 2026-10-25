# frozen_string_literal: true

module Api
  module V1
    # Blocking hides a player's timeline posts and comments from the blocker.
    # Both writes are idempotent: blocking twice or unblocking someone who
    # isn't blocked just answers with the current state.
    class BlocksController < BaseController
      def index
        blocks, meta = paginate(current_user.user_blocks.includes(blocked: { avatar_attachment: :blob })
                                            .order(created_at: :desc, id: :desc))
        render_collection UserBlockResource, blocks, meta: meta
      end

      def create
        blocked = User.find(params[:user_id])
        return render_error(:unprocessable_content, "cannot_block_self") if blocked == current_user

        created = !current_user.user_blocks.exists?(blocked: blocked)
        block = UserBlock.block!(current_user, blocked)
        track_event "api.user.blocked", blocked_id: blocked.id if created
        render_resource UserBlockResource, block, status: created ? :created : :ok
      end

      def destroy
        blocked = User.find(params[:user_id])
        current_user.user_blocks.where(blocked: blocked).destroy_all
        track_event "api.user.unblocked", blocked_id: blocked.id
        head :no_content
      end
    end
  end
end
