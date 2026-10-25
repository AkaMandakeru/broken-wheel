# frozen_string_literal: true

module Api
  module V1
    module Challenges
      # A challenge's timeline. Only its participants may read or post, as on
      # the web; posts and comments from players the viewer blocked are hidden.
      class TimelinePostsController < Challenges::BaseController
        idempotent only: :create

        def index
          scope = @challenge.timeline_posts.visible_to(current_user)
                            .includes(:workout, user: { avatar_attachment: :blob }, images_attachments: :blob,
                                      timeline_post_comments: { user: { avatar_attachment: :blob } })
          posts, meta = paginate(scope.order(created_at: :desc, id: :desc))

          render_collection TimelinePostResource, posts, meta: meta, blocked_ids: blocked_ids
        end

        def create
          attributes = post_params
          signed_ids = Array(attributes.delete(:images)).compact_blank
          if signed_ids.size > TimelinePost::MAX_IMAGES
            return render_error(:unprocessable_content, "validation_failed",
                                fields: { images: [ I18n.t("activerecord.errors.models.timeline_post.attributes.images.too_many", count: TimelinePost::MAX_IMAGES) ] })
          end

          post = @challenge.timeline_posts.build(attributes.merge(user: current_user))
          signed_ids.each { |signed_id| post.images.attach(UploadedImage.find!(signed_id, user: current_user, purpose: "timeline_post")) }
          return render_invalid(post) unless post.save

          Analytics.track(user: current_user, event: "post_created", properties: { challenge_id: @challenge.id })
          track_event "api.timeline_post.created", challenge_id: @challenge.id, timeline_post_id: post.id
          render_resource TimelinePostResource, post, status: :created, blocked_ids: blocked_ids
        rescue UploadedImage::Invalid => error
          render_error :unprocessable_content, "invalid_upload", fields: { error.attribute => [ error.message ] }
        end

        private

        def post_params
          params.expect(timeline_post: [ :content, :workout_id, images: [] ]).to_h.symbolize_keys
        end
      end
    end
  end
end
