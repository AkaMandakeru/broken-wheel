# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 events", type: :request do
  let(:user) { build_user }
  let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

  # Creating an event broadcasts a push; nothing to send in these specs.
  before { allow(PushNotifier).to receive(:broadcast) }

  def build_event(title: "City 10k", status: "upcoming", date: 10.days.from_now, distances: [])
    Event.create!(title: title, sport: "run", status: status, event_date: date, location: "Downtown", distances: distances)
  end

  path "/api/v1/events" do
    get "Upcoming events (soonest first) and past ones (latest first)" do
      tags "Events"
      produces "application/json"

      response "200", "events" do
        schema SocialSchemas::EVENT_LISTS

        before do
          later = build_event(title: "Later", date: 20.days.from_now)
          build_event(title: "Sooner", date: 5.days.from_now)
          build_event(title: "Done", status: "completed", date: 5.days.ago)
          user.event_participations.create!(event: later)
        end

        run_test! do
          expect(json_data["upcoming"].pluck("title")).to eq([ "Sooner", "Later" ])
          expect(json_data["past"].pluck("title")).to eq([ "Done" ])
          expect(json_data["upcoming"].last["my_participation"]).to include("status" => "going")
          expect(json_data["upcoming"].last["participants_count"]).to eq(1)
        end
      end

      response "403", "events are switched off" do
        schema "$ref" => "#/components/schemas/error"
        before { FeatureFlag.set(:events, false) }

        run_test! do
          expect(json_error_code).to eq("feature_disabled")
        end
      end

      response "401", "not signed in" do
        schema "$ref" => "#/components/schemas/error"
        let(:Authorization) { nil }

        run_test!
      end
    end
  end

  path "/api/v1/events/{id}" do
    parameter name: :id, in: :path, schema: { type: :integer }

    get "One event: who's going, distance counts and the viewer's participation" do
      tags "Events"
      produces "application/json"

      response "200", "the event" do
        schema SocialSchemas.data(SocialSchemas::EVENT_DETAIL)
        let(:event) { build_event(distances: [ 5, 10 ]) }
        let(:id) { event.id }

        before do
          build_user(first_name: "Bia").event_participations.create!(event: event, selected_distance_km: 10)
          user.event_participations.create!(event: event, selected_distance_km: 5)
          build_workout(user, date: Date.current)
        end

        run_test! do
          expect(json_data["distance_counts"]).to eq([ { "distance_km" => 5.0, "count" => 1 }, { "distance_km" => 10.0, "count" => 1 } ])
          expect(json_data["my_participation"]).to include("status" => "going", "selected_distance_km" => 5.0)
          expect(json_data["participants"].size).to eq(2)
          expect(json_data["available_workouts"].size).to eq(1)
        end
      end

      response "404", "no such event" do
        schema "$ref" => "#/components/schemas/error"
        let(:id) { 0 }

        run_test!
      end
    end
  end

  path "/api/v1/events/{event_id}/participation" do
    parameter name: :event_id, in: :path, schema: { type: :integer }

    post "RSVP, optionally with the result straight away" do
      tags "Events"
      consumes "application/json"
      produces "application/json"
      parameter "$ref" => "#/components/parameters/idempotency_key"
      parameter name: :body, in: :body, required: false, schema: SocialSchemas::PARTICIPATION_INPUT

      let(:event) { build_event }
      let(:event_id) { event.id }

      response "201", "going" do
        schema SocialSchemas.data(SocialSchemas::EVENT_DETAIL)
        let(:body) { {} }

        run_test! do
          expect(json_data["my_participation"]).to include("status" => "going")
          expect(json_data["participants_count"]).to eq(1)
        end
      end

      response "201", "recorded with a result" do
        schema SocialSchemas.data(SocialSchemas::EVENT_DETAIL)
        let(:workout) { build_workout(user, date: Date.current, km: 10, minutes: 50) }
        let(:body) { { participation: { workout_id: workout.id, bib_number: "123" } } }

        run_test! do
          expect(json_data["my_participation"]).to include("status" => "completed", "bib_number" => "123", "pace_min_per_km" => 5.0)
          expect(json_data["available_workouts"]).to eq([])
        end
      end

      response "409", "already going" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { {} }
        before { user.event_participations.create!(event: event) }

        run_test! do
          expect(json_error_code).to eq("already_going")
        end
      end

      response "422", "a distance must be picked" do
        schema "$ref" => "#/components/schemas/error"
        let(:event) { build_event(distances: [ 5, 10 ]) }
        let(:body) { { participation: { selected_distance_km: 7 } } }

        run_test! do
          expect(json_body.dig("error", "fields")).to have_key("selected_distance_km")
        end
      end
    end

    patch "Link (or change) the result workout" do
      tags "Events"
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: SocialSchemas::PARTICIPATION_INPUT

      let(:event) { build_event }
      let(:event_id) { event.id }

      response "200", "result linked" do
        schema SocialSchemas.data(SocialSchemas::EVENT_DETAIL)
        let(:body) { { participation: { workout_id: build_workout(user, date: Date.current).id } } }
        before { user.event_participations.create!(event: event) }

        run_test! do
          expect(json_data["my_participation"]["status"]).to eq("completed")
        end
      end

      response "422", "someone else's workout" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { participation: { workout_id: build_workout(build_user, date: Date.current).id } } }
        before { user.event_participations.create!(event: event) }

        run_test! do
          expect(json_body.dig("error", "fields")).to have_key("workout")
        end
      end

      response "404", "not going" do
        schema "$ref" => "#/components/schemas/error"
        let(:body) { { participation: { notes: "x" } } }

        run_test! do
          expect(json_error_code).to eq("not_going")
        end
      end
    end

    delete "Drop out" do
      tags "Events"

      response "204", "removed" do
        let(:event) { build_event }
        let(:event_id) { event.id }
        before { user.event_participations.create!(event: event) }

        run_test! do
          expect(user.event_participations.reload).to be_empty
        end
      end
    end
  end

  it "tracks a recorded participation like the web" do
    allow(Analytics).to receive(:track)
    event = build_event

    post "/api/v1/events/#{event.id}/participation", headers: api_headers(user), as: :json

    expect(Analytics).to have_received(:track).with(hash_including(event: "event_participation_recorded"))
  end
end
