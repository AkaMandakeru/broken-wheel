# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin participation rewards", type: :request do
  include ActiveJob::TestHelper

  before { clear_enqueued_jobs and clear_performed_jobs }

  let(:admin) { build_user(admin: true) }
  let(:season) { build_season }

  before { sign_in admin }

  it "creates one from the form, with no level and no threshold" do
    post admin_season_season_rewards_path(season), params: {
      season_reward: {
        unlock_kind: "participation", reward_type: "cosmetic",
        reward_key: "spring_banner", name: "Spring Banner", track: "free"
      }
    }

    reward = season.season_rewards.sole
    expect(reward).to be_participation
    expect(reward.level).to be_nil
    expect(reward.join_window).to be_nil
  end

  it "accepts a join window" do
    post admin_season_season_rewards_path(season), params: {
      season_reward: {
        unlock_kind: "participation", reward_type: "cosmetic", reward_key: "week_banner",
        name: "Week Banner", track: "free",
        joined_from: "2026-09-01T00:00", joined_until: "2026-09-07T23:59"
      }
    }

    expect(season.season_rewards.sole.join_window).to be_present
  end

  it "queues the hand-out when the button is pressed" do
    reward = season.season_rewards.create!(
      reward_type: "coins", reward_key: "welcome", name: "Welcome", coins: 50,
      unlock_kind: "participation", track: "free"
    )

    expect {
      post distribute_admin_season_season_reward_path(season, reward)
    }.to have_enqueued_job(DistributeSeasonRewardJob).with(reward.id)

    expect(response).to redirect_to(admin_season_path(season))
    expect(flash[:notice]).to be_present
  end

  # Every other kind has a threshold the player has to clear, so handing one out
  # on demand would skip the thing that makes it worth having.
  it "refuses to hand out a level reward" do
    reward = season.season_rewards.create!(
      reward_type: "coins", reward_key: "lvl5", name: "L5", coins: 50,
      unlock_kind: "level", level: 5, track: "free"
    )

    expect {
      post distribute_admin_season_season_reward_path(season, reward)
    }.not_to have_enqueued_job(DistributeSeasonRewardJob)

    expect(flash[:alert]).to be_present
  end

  it "shows the button only for participation rewards" do
    season.season_rewards.create!(reward_type: "coins", reward_key: "everyone", name: "Everyone",
                                 coins: 10, unlock_kind: "participation", track: "free")
    season.season_rewards.create!(reward_type: "coins", reward_key: "lvl3", name: "L3",
                                  coins: 10, unlock_kind: "level", level: 3, track: "free")

    get admin_season_path(season)

    expect(response.body.scan(I18n.t("admin.seasons.rewards.distribute")).size).to eq(1)
  end

  it "keeps a non-admin out" do
    sign_out admin
    sign_in build_user
    reward = season.season_rewards.create!(reward_type: "coins", reward_key: "w", name: "W", coins: 5,
                                           unlock_kind: "participation", track: "free")

    expect {
      post distribute_admin_season_season_reward_path(season, reward)
    }.not_to have_enqueued_job(DistributeSeasonRewardJob)
  end
end
