# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 challenge timeline", type: :request do
  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
  let(:challenge) { build_challenge(key: "timeline_test", requirements: [ { metric: "distance_km", target: 20 } ]) }
  let(:friend) { build_user(first_name: "Bia") }

  before do
    ChallengeEnroller.call(user, challenge)
    ChallengeEnroller.call(friend, challenge)
  end

  def uploaded_image(owner, purpose: "timeline_post")
    ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("season_cover.png").open, filename: "run.png", content_type: "image/png",
      metadata: { "uploader_id" => owner.id, "purpose" => purpose }
    )
  end

  path "/api/v1/challenges/{challenge_id}/timeline" do
    parameter name: :challenge_id, in: :path, schema: { type: :integer }

    get "The challenge's timeline, newest first (participants only)" do
      tags "Timeline"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/cursor"
      parameter "$ref" => "#/components/parameters/limit"

      response "200", "a page of posts" do
        schema SocialSchemas.page(SocialSchemas::TIMELINE_POST)
        let(:challenge_id) { challenge.id }

        before do
          workout = build_workout(friend, date: Date.new(2026, 8, 2), km: 8)
          post = challenge.timeline_posts.create!(user: friend, content: "Morning run", workout: workout)
          post.timeline_post_comments.create!(user: user, content: "Nice!")
          challenge.timeline_posts.create!(user: user, content: "My first post")
        end

        run_test! do
          expect(json_data.pluck("content")).to eq([ "My first post", "Morning run" ])
          friend_post = json_data.last
          expect(friend_post["user"]["first_name"]).to eq("Bia")
          expect(friend_post["workout"]).to include("distance_km" => 8.0)
          expect(friend_post["comments"].first).to include("content" => "Nice!", "mine" => true)
        end
      end

      response "403", "not a participant" do
        schema "$ref" => "#/components/schemas/error"
        let(:challenge_id) { challenge.id }
        let(:Authorization) { "Bearer #{api_sign_in(build_user).access_token}" }

        run_test! do
          expect(json_error_code).to eq("not_participant")
        end
      end

      response "404", "no such challenge" do
        schema "$ref" => "#/components/schemas/error"
        let(:challenge_id) { 0 }

        run_test!
      end
    end

    post "Post on the timeline" do
      tags "Timeline"
      consumes "application/json"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"
      parameter name: :body, in: :body, schema: {
        type: :object, required: [ "timeline_post" ],
        properties: {
          timeline_post: {
            type: :object,
            description: "Needs content, images or both",
            properties: {
              content: { type: :string, maxLength: TimelinePost::MAX_CONTENT_LENGTH },
              workout_id: { type: :integer, description: "One of the author's own workouts" },
              images: { type: :array, maxItems: TimelinePost::MAX_IMAGES, items: { type: :string },
                        description: "signed_ids from POST /api/v1/uploads with purpose timeline_post" }
            }
          }
        }
      }

      response "201", "posted" do
        schema SocialSchemas.data(SocialSchemas::TIMELINE_POST)
        let(:challenge_id) { challenge.id }
        let(:workout) { build_workout(user, date: Date.new(2026, 8, 4)) }
        let(:body) { { timeline_post: { content: "10k done", workout_id: workout.id, images: [ uploaded_image(user).signed_id ] } } }

        run_test! do
          expect(json_data).to include("content" => "10k done", "mine" => true)
          expect(json_data["images"].first.keys).to contain_exactly("original", "thumb", "large")
          expect(TimelinePost.last.images.count).to eq(1)
        end
      end

      response "422", "empty post" do
        schema "$ref" => "#/components/schemas/error"
        let(:challenge_id) { challenge.id }
        let(:body) { { timeline_post: { content: "" } } }

        run_test! do
          expect(json_body.dig("error", "fields")).to have_key("content")
        end
      end
    end
  end

  it "refuses someone else's upload" do
    post "/api/v1/challenges/#{challenge.id}/timeline", headers: api_headers(user), as: :json,
                                                        params: { timeline_post: { content: "x", images: [ uploaded_image(friend).signed_id ] } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_error_code).to eq("invalid_upload")
  end

  it "refuses more than #{TimelinePost::MAX_IMAGES} images" do
    images = Array.new(TimelinePost::MAX_IMAGES + 1) { "signed-#{it}" }
    post "/api/v1/challenges/#{challenge.id}/timeline", headers: api_headers(user), as: :json,
                                                        params: { timeline_post: { content: "x", images: images } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body.dig("error", "fields")).to have_key("images")
  end

  it "refuses another player's workout" do
    workout = build_workout(friend, date: Date.new(2026, 8, 4))
    post "/api/v1/challenges/#{challenge.id}/timeline", headers: api_headers(user), as: :json,
                                                        params: { timeline_post: { content: "x", workout_id: workout.id } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(json_body.dig("error", "fields")).to have_key("workout")
  end

  it "hides posts and comments from players the viewer blocked, but not the other way round" do
    post_by_friend = challenge.timeline_posts.create!(user: friend, content: "Blocked post")
    own_post = challenge.timeline_posts.create!(user: user, content: "Own post")
    own_post.timeline_post_comments.create!(user: friend, content: "Blocked comment")
    UserBlock.block!(user, friend)

    get "/api/v1/challenges/#{challenge.id}/timeline", headers: api_headers(user)
    expect(json_data.pluck("id")).to eq([ own_post.id ])
    expect(json_data.first["comments"]).to be_empty

    get "/api/v1/challenges/#{challenge.id}/timeline", headers: api_headers(friend)
    expect(json_data.pluck("id")).to contain_exactly(own_post.id, post_by_friend.id)
  end

  it "pages with a cursor" do
    3.times { |index| challenge.timeline_posts.create!(user: friend, content: "Post #{index}") }

    get "/api/v1/challenges/#{challenge.id}/timeline", params: { limit: 2 }, headers: api_headers(user)
    expect(json_data.size).to eq(2)

    get "/api/v1/challenges/#{challenge.id}/timeline", params: { limit: 2, cursor: json_body.dig("meta", "next_cursor") },
                                                       headers: api_headers(user)
    expect(json_data.pluck("content")).to eq([ "Post 0" ])
  end

  path "/api/v1/challenges/{challenge_id}/timeline/{timeline_post_id}/comments" do
    parameter name: :challenge_id, in: :path, schema: { type: :integer }
    parameter name: :timeline_post_id, in: :path, schema: { type: :integer }

    post "Comment on a post" do
      tags "Timeline"
      consumes "application/json"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"
      parameter name: :body, in: :body, schema: {
        type: :object, required: [ "comment" ],
        properties: { comment: { type: :object, required: [ "content" ], properties: { content: { type: :string, maxLength: TimelinePostComment::MAX_CONTENT_LENGTH } } } }
      }

      let(:timeline_post) { challenge.timeline_posts.create!(user: friend, content: "Morning run") }
      let(:challenge_id) { challenge.id }
      let(:timeline_post_id) { timeline_post.id }

      response "201", "commented" do
        schema SocialSchemas.data(SocialSchemas::TIMELINE_COMMENT)
        let(:body) { { comment: { content: "Great pace" } } }

        run_test! do
          expect(timeline_post.timeline_post_comments.pluck(:content)).to eq([ "Great pace" ])
        end
      end

      response "422", "empty comment" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { comment: { content: " " } } }

        run_test!
      end

      response "404", "post from another challenge" do
        schema "$ref" => "#/components/schemas/error"
        let(:timeline_post_id) { build_challenge(key: "elsewhere", requirements: [ { metric: "distance_km", target: 1 } ]).timeline_posts.create!(user: friend, content: "x").id }
        let(:body) { { comment: { content: "Hi" } } }

        run_test!
      end
    end
  end
end
