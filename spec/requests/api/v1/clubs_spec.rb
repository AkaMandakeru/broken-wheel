# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 clubs", type: :request do
  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }
  let(:founder) { build_user(first_name: "Bia") }

  def found_club(name, sport: "run", by: founder)
    Club.new(name: name, sport: sport).tap { |club| Clubs::Membership.create_with_founder(club, by) }
  end

  path "/api/v1/clubs" do
    get "Clubs, biggest first, narrowed to the viewer's sports" do
      tags "Clubs"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/cursor"
      parameter "$ref" => "#/components/parameters/limit"

      response "200", "a page of clubs" do
        schema SocialSchemas.page(SocialSchemas::CLUB)

        before do
          user.update!(sports: [ "run" ])
          runners = found_club("Runners")
          Clubs::Membership.new(runners, user).join
          found_club("Small runners")
          found_club("Cyclists", sport: "bike")
        end

        run_test! do
          expect(json_data.pluck("name")).to eq([ "Runners", "Small runners" ])
          expect(json_data.pluck("member")).to eq([ true, false ])
          expect(json_data.first["member_count"]).to eq(2)
        end
      end

      response "403", "clubs are switched off" do
        schema "$ref" => "#/components/schemas/error"
        before { FeatureFlag.set(:clubs, false) }

        run_test! do
          expect(json_error_code).to eq("feature_disabled")
        end
      end
    end

    post "Found a club (the founder becomes its admin)" do
      tags "Clubs"
      consumes "application/json"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"
      parameter name: :body, in: :body, schema: {
        type: :object, required: [ "club" ],
        properties: {
          club: {
            type: :object, required: [ "name" ],
            properties: { name: { type: :string, maxLength: 100 }, description: { type: :string }, sport: { type: :string, enum: Club::SPORTS } }
          }
        }
      }

      response "201", "created" do
        schema SocialSchemas.data(SocialSchemas::CLUB_DETAIL)
        let(:body) { { club: { name: "Dawn Patrol", sport: "run", description: "6am runs" } } }

        run_test! do
          expect(json_data).to include("name" => "Dawn Patrol", "member_count" => 1, "member" => true)
          expect(json_data["my_membership"]["role"]).to eq("admin")
        end
      end

      response "422", "no name" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { club: { name: "" } } }

        run_test! do
          expect(json_body.dig("error", "fields")).to have_key("name")
          expect(Club.count).to eq(0)
        end
      end
    end
  end

  path "/api/v1/clubs/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }

    get "One club with its members" do
      tags "Clubs"
      produces "application/json"

      response "200", "the club" do
        schema SocialSchemas.data(SocialSchemas::CLUB_DETAIL)
        let(:id) { found_club("Runners").id }

        run_test! do
          expect(json_data["members"].map { |row| [ row["role"], row["user"]["first_name"] ] }).to eq([ [ "admin", "Bia" ] ])
          expect(json_data["my_membership"]).to be_nil
          expect(json_data["members"].first["user"]).not_to have_key("email")
        end
      end

      response "404", "no such club" do
        schema "$ref" => "#/components/schemas/error"
        let(:id) { 0 }

        run_test!
      end
    end
  end

  path "/api/v1/clubs/{id}/join" do
    parameter name: :id, in: :path, schema: { type: :integer }

    post "Join a club" do
      tags "Clubs"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"

      let(:club) { found_club("Runners") }
      let(:id) { club.id }

      response "201", "joined" do
        schema SocialSchemas.data(SocialSchemas::CLUB_DETAIL)

        run_test! do
          expect(json_data).to include("member" => true, "member_count" => 2)
          expect(json_data["my_membership"]["role"]).to eq("member")
        end
      end

      response "409", "already a member" do
        schema "$ref" => "#/components/schemas/error"
        before { Clubs::Membership.new(club, user).join }

        run_test! do
          expect(json_error_code).to eq("already_member")
          expect(club.reload.member_count).to eq(2)
        end
      end
    end
  end

  it "evaluates season objectives and tracks the join, like the web" do
    club = found_club("Runners")
    allow(SeasonObjectives).to receive(:enqueue_for)
    allow(Analytics).to receive(:track)

    post "/api/v1/clubs/#{club.id}/join", headers: api_headers(user)

    expect(SeasonObjectives).to have_received(:enqueue_for).with(user, kinds: %w[join_club club_workout])
    expect(Analytics).to have_received(:track).with(hash_including(event: "club_joined"))
  end

  path "/api/v1/clubs/{id}/membership" do
    parameter name: :id, in: :path, schema: { type: :integer }

    delete "Leave a club" do
      tags "Clubs"

      let(:club) { found_club("Runners") }
      let(:id) { club.id }

      response "204", "left" do
        before { Clubs::Membership.new(club, user).join }

        run_test! do
          expect(club.reload.member_count).to eq(1)
          expect(user.club_memberships).to be_empty
        end
      end

      response "404", "not a member" do
        schema "$ref" => "#/components/schemas/error"

        run_test! do
          expect(json_error_code).to eq("not_member")
        end
      end
    end
  end
end
