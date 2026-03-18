# frozen_string_literal: true

class TimelinePostsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_challenge
  before_action :ensure_participant, only: [:index, :create]

  def index
    @timeline_posts = @challenge.timeline_posts.includes(:user, :workout, images_attachments: :blob).order(created_at: :desc)
    @timeline_post = TimelinePost.new
  end

  def create
    @timeline_post = @challenge.timeline_posts.build(timeline_post_params)
    @timeline_post.user = current_user
    if @timeline_post.save
      redirect_to challenge_timeline_posts_path(@challenge), notice: "Post shared!"
    else
      @timeline_posts = @challenge.timeline_posts.includes(:user, :workout).order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  private

  def set_challenge
    @challenge = Challenge.find(params[:challenge_id])
  end

  def ensure_participant
    return if current_user.challenge_participations.exists?(challenge_id: @challenge.id)

    redirect_to challenge_path(@challenge), alert: "Join the challenge to view and post on the timeline."
  end

  def timeline_post_params
    params.require(:timeline_post).permit(:content, :workout_id, images: [])
  end
end
