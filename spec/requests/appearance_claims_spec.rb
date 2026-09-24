# frozen_string_literal: true

require "rails_helper"

# A cosmetic the season offers, taken by the player from their own locker.
RSpec.describe "Claiming a cosmetic", type: :request do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs and clear_performed_jobs }

  let(:user) { build_user }
  let(:season) { build_season(status: "active") }
  let!(:banner) { build_cosmetic(key: "spring_banner", kind: "banner", rarity: "epic") }

  def offer(cosmetic = banner, claimable: true, from: nil, to: nil, track: "free", on: season)
    on.season_rewards.create!(
      reward_type: "cosmetic", reward_key: cosmetic.key, name: cosmetic.name,
      unlock_kind: "participation", track: track, claimable: claimable,
      joined_from: from, joined_until: to
    )
  end

  def join(on: season)
    SeasonProgressService.ensure_participation(user, on)
  end

  before { sign_in user }

  describe "the locker" do
    it "offers it with a claim button once the member has joined" do
      offer
      join

      get profile_appearance_path

      expect(response.body).to include("Spring banner")
      expect(response.body).to include(I18n.t("appearances.show.claim"))
      expect(response.body).to include(claim_profile_appearance_path)
    end

    it "offers nothing to someone who never joined the season" do
      offer

      get profile_appearance_path

      expect(response.body).not_to include(claim_profile_appearance_path)
    end

    # It is not locked — the player can have it right now — so a padlock would
    # be a lie. It must appear once, in the claimable section only.
    it "does not also list it among the locked ones" do
      offer
      join

      get profile_appearance_path

      expect(response.body.scan("Spring banner").size).to eq(1)
      expect(response.body).not_to include(I18n.t("appearances.show.not_yet_offered"))
    end

    it "stops offering it once claimed" do
      offer
      join
      post claim_profile_appearance_path, params: { kind: "banner", key: banner.key }

      follow_redirect!

      expect(user.reload.owns_cosmetic?("spring_banner")).to be(true)
      expect(response.body).not_to include(claim_profile_appearance_path)
    end

    it "leaves a pushed reward out of the claim section" do
      offer(claimable: false)
      join

      get profile_appearance_path

      expect(response.body).not_to include(claim_profile_appearance_path)
    end

    # Season.browsable keeps the most recent finished season reachable, so the
    # offer has to sit on one older than that to be genuinely out of reach.
    it "offers nothing from a season the player can no longer open" do
      build_season(key: "last_month", status: "ended", starts_at: 2.months.ago, ends_at: 1.month.ago)
      ancient = build_season(key: "ancient", status: "ended", starts_at: 2.years.ago, ends_at: 23.months.ago)
      offer(on: ancient)
      join(on: ancient)

      get profile_appearance_path

      expect(Season.browsable).not_to include(ancient)
      expect(response.body).not_to include(claim_profile_appearance_path)
    end
  end

  describe "claiming" do
    it "hands the cosmetic over and makes it equippable" do
      offer
      join

      post claim_profile_appearance_path, params: { kind: "banner", key: banner.key }

      expect(user.reload.owns_cosmetic?("spring_banner")).to be(true)
      expect(user.equip_cosmetic!("banner", "spring_banner")).to be(true)
      expect(flash[:notice]).to eq(I18n.t("appearances.flashes.claimed"))
    end

    it "grants it once, however many times the button is pressed" do
      offer
      join

      2.times { post claim_profile_appearance_path, params: { kind: "banner", key: banner.key } }

      expect(user.reload.user_cosmetics.where(cosmetic: banner).count).to eq(1)
    end

    # The button is rendered from a page that may be stale, so the claim itself
    # re-checks rather than trusting what it was handed.
    it "refuses a cosmetic the season never offered" do
      other = build_cosmetic(key: "not_offered", kind: "banner")
      join

      post claim_profile_appearance_path, params: { kind: "banner", key: other.key }

      expect(user.reload.owns_cosmetic?("not_offered")).to be(false)
      expect(flash[:alert]).to be_present
    end

    it "refuses when the member never joined the season" do
      offer

      post claim_profile_appearance_path, params: { kind: "banner", key: banner.key }

      expect(user.reload.owns_cosmetic?("spring_banner")).to be(false)
    end

    it "refuses one whose join window excludes the member" do
      join
      offer(from: 1.day.from_now)

      post claim_profile_appearance_path, params: { kind: "banner", key: banner.key }

      expect(user.reload.owns_cosmetic?("spring_banner")).to be(false)
    end

    it "refuses a premium offer to a free member" do
      offer(track: "premium")
      join

      post claim_profile_appearance_path, params: { kind: "banner", key: banner.key }

      expect(user.reload.owns_cosmetic?("spring_banner")).to be(false)
    end

    # The locker hides an unrenderable cosmetic because it cannot be worn. The
    # claim path used to miss that check and hand it over anyway, leaving the
    # player owning something that never showed up anywhere.
    it "refuses one the locker would not show because it cannot be worn" do
      pending_art = build_cosmetic(key: "no_art_yet", kind: "banner", renderable: false)
      offer(pending_art)
      join

      post claim_profile_appearance_path, params: { kind: "banner", key: pending_art.key }

      expect(user.reload.owns_cosmetic?("no_art_yet")).to be(false)
      expect(flash[:alert]).to be_present
    end

    it "refuses a pushed reward — that one is not the player's to take" do
      offer(claimable: false)
      join

      post claim_profile_appearance_path, params: { kind: "banner", key: banner.key }

      expect(user.reload.owns_cosmetic?("spring_banner")).to be(false)
    end

    it "needs a signed-in member" do
      offer
      join
      sign_out user

      post claim_profile_appearance_path, params: { kind: "banner", key: banner.key }

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "a claimable reward is never pushed" do
    it "is not handed over by joining" do
      offer
      participation = join

      perform_enqueued_jobs

      expect(participation.reload.season_reward_grants.count).to eq(0)
      expect(user.reload.owns_cosmetic?("spring_banner")).to be(false)
    end

    it "is not handed over by the admin distribute job either" do
      reward = offer
      join

      DistributeSeasonRewardJob.perform_now(reward.id)

      expect(user.reload.owns_cosmetic?("spring_banner")).to be(false)
    end
  end
end
