# frozen_string_literal: true

require "rails_helper"

# Challenges still complete on their own; the XP waits to be collected.
RSpec.describe "Claiming season XP", type: :request do
  let(:user) { build_user }
  let(:season) { build_season }
  let(:participation) { SeasonProgressService.ensure_participation(user, season) }

  let(:challenge) do
    build_challenge(key: "run_20km", sport: "run", requirements: [ { metric: "distance_km", target: 20 } ])
  end

  let!(:season_challenge) do
    season.season_challenges.create!(challenge: challenge, category: "monthly", xp_reward: 500, fragment_reward: 10)
  end

  def complete_the_challenge
    participation
    ChallengeEnroller.call(user, challenge, season: season)
    3.times { |i| build_workout(user, date: Date.new(2026, 8, 3 + i), km: 8) }
    RecomputeChallengeProgress.new(user.challenge_participations.find_by(challenge: challenge, season: season)).call
    SeasonProgressService.new(participation).recalculate
    participation.reload
  end

  describe "completing a challenge" do
    it "still completes automatically" do
      complete_the_challenge

      expect(participation.season_challenge_completions.count).to eq(1)
    end

    # The whole point: the number must not move until the player collects it.
    it "leaves the XP uncollected" do
      complete_the_challenge

      expect(participation.unclaimed_count).to eq(1)
      expect(participation.unclaimed_xp).to eq(500)
      expect(participation.xp_breakdown["challenges"]).to eq(0)
    end

    it "withholds the medal fragments too" do
      complete_the_challenge

      expect(participation.medal_fragments).to eq(0)
    end
  end

  describe "an archived season" do
    before do
      complete_the_challenge
      sign_in user
      # This season finishes, then a later one finishes behind it — pushing it
      # past the one-season archive depth.
      season.update_columns(status: "ended")
      build_season(status: "ended", starts_at: Date.new(2026, 9, 1), ends_at: Date.new(2026, 9, 30))
      build_season(status: "active", starts_at: Date.new(2026, 10, 1), ends_at: Date.new(2026, 10, 31))
    end

    it "refuses the claim" do
      expect { post season_claims_path(season) }
        .not_to change { participation.reload.xp }

      expect(response).to redirect_to(seasons_path)
    end

    it "answers 404 to the in-page claim" do
      post season_claims_path(season), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "collecting it" do
    before do
      complete_the_challenge
      sign_in user
    end

    it "adds the XP and clears the pending list" do
      post season_claims_path(season)

      expect(participation.reload.xp_breakdown["challenges"]).to eq(500)
      expect(participation.unclaimed_count).to eq(0)
    end

    it "releases the fragments as well" do
      post season_claims_path(season)

      expect(participation.reload.medal_fragments).to eq(10)
    end

    it "answers JSON with what the animation needs" do
      post season_claims_path(season), as: :json

      body = response.parsed_body
      expect(body).to include("claimed" => 1, "xp_gained" => 500, "remaining" => 0)
      expect(body["xp"]).to eq(participation.reload.xp)
      expect(body).to have_key("progress_percent")
      expect(body).to have_key("level")
    end

    it "redirects back to the season for a plain form post" do
      post season_claims_path(season)

      expect(response).to redirect_to(season_path(season))
    end

    # A double-click or a replayed request must not pay twice.
    it "is idempotent" do
      post season_claims_path(season)
      xp = participation.reload.xp

      post season_claims_path(season), as: :json

      expect(response.parsed_body).to include("claimed" => 0, "xp_gained" => 0)
      expect(participation.reload.xp).to eq(xp)
    end

    it "collects a single completion by id" do
      completion = participation.season_challenge_completions.first

      post season_claim_path(season, completion), as: :json

      expect(response.parsed_body["claimed"]).to eq(1)
      expect(completion.reload).to be_claimed
    end
  end

  describe "with several pending" do
    let(:other_challenge) do
      build_challenge(key: "run_10km", sport: "run", requirements: [ { metric: "distance_km", target: 10 } ])
    end

    before do
      season.season_challenges.create!(challenge: other_challenge, category: "monthly", xp_reward: 300)
      complete_the_challenge
      ChallengeEnroller.call(user, other_challenge, season: season)
      RecomputeChallengeProgress.new(user.challenge_participations.find_by(challenge: other_challenge, season: season)).call
      SeasonProgressService.new(participation).recalculate
      sign_in user
    end

    it "collects only the one asked for" do
      first = participation.reload.unclaimed_completions.first

      post season_claim_path(season, first), as: :json

      expect(response.parsed_body["remaining"]).to eq(1)
    end

    it "collects everything at once" do
      post season_claims_path(season), as: :json

      expect(response.parsed_body).to include("claimed" => 2, "xp_gained" => 800, "remaining" => 0)
    end
  end

  describe "the season page" do
    it "shows the pending panel" do
      complete_the_challenge
      sign_in user

      get season_path(season)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.claim.title")))
      expect(response.body).to include("xp-claim")
    end

    it "hides the panel when nothing is pending" do
      participation
      sign_in user

      get season_path(season)

      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("seasons.claim.title")))
    end
  end

  describe "guarding other people's XP" do
    it "will not collect a completion belonging to someone else" do
      complete_the_challenge
      stranger = build_user
      SeasonProgressService.ensure_participation(stranger, season)
      victim_completion = participation.season_challenge_completions.first

      sign_in stranger
      post season_claim_path(season, victim_completion), as: :json

      expect(response.parsed_body["claimed"]).to eq(0)
      expect(victim_completion.reload).not_to be_claimed
    end

    it "turns away someone who never joined the season" do
      outsider = build_user
      sign_in outsider

      post season_claims_path(season), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "after importing workouts" do
    it "lands on the active season, where the new XP is waiting" do
      user.create_strava_token!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now.to_i)
      season.update!(status: "active")
      sign_in user

      activity = double(
        id: 99, sport_type: "Run", distance: 12_000.0, moving_time: 3600,
        start_date_local: Time.zone.parse("2026-08-05T08:00:00"),
        start_date: Time.zone.parse("2026-08-05T11:00:00"),
        to_h: { "id" => 99, "sport_type" => "Run" }
      )
      service = instance_double(StravaService)
      allow(StravaService).to receive(:new).and_return(service)
      allow(service).to receive(:activity).with("99").and_return(activity)

      post import_strava_workouts_path, params: { activity_ids: [ "99" ] }

      expect(response).to redirect_to(season_path(season))
    end
  end

  describe "existing progress" do
    # Everything completed before claiming existed was backfilled as collected,
    # so nobody logs in to find their XP has dropped.
    it "treats a pre-existing completion as already collected" do
      complete_the_challenge
      participation.season_challenge_completions.update_all(claimed_at: Time.current)
      SeasonProgressService.new(participation).recalculate

      expect(participation.reload.unclaimed_count).to eq(0)
      expect(participation.xp_breakdown["challenges"]).to eq(500)
    end
  end
end
