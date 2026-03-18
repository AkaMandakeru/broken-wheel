# frozen_string_literal: true

class TimelinePostCommentsController < ApplicationController
  before_action :authenticate_user!

  def create
    @timeline_post = TimelinePost.find(params[:timeline_post_id])
    @comment = @timeline_post.timeline_post_comments.build(comment_params)
    @comment.user = current_user
    if @comment.save
      redirect_to challenge_timeline_posts_path(@timeline_post.challenge), notice: "Comment added!"
    else
      redirect_to challenge_timeline_posts_path(@timeline_post.challenge), alert: @comment.errors.full_messages.join(", ")
    end
  end

  private

  def comment_params
    params.require(:timeline_post_comment).permit(:content)
  end
end
