# frozen_string_literal: true

module Api
  module V1
    module Challenges
      class CommentsController < Challenges::BaseController
        idempotent only: :create

        def create
          post = @challenge.timeline_posts.visible_to(current_user).find(params[:timeline_post_id])
          comment = post.timeline_post_comments.build(content: params.expect(comment: [ :content ])[:content], user: current_user)
          return render_invalid(comment) unless comment.save

          track_event "api.timeline_comment.created", timeline_post_id: post.id, comment_id: comment.id
          render_resource TimelineCommentResource, comment, status: :created
        end
      end
    end
  end
end
