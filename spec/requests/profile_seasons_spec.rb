# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profile & achievements", type: :request do
  let(:user) { build_user }

  def participate(season, fragments:, level: 1, completion: 0)
    participation = SeasonParticipation.create!(user: user, season: season, level: level)
    participation.update!(medal_fragments: fragments, completion_percent: completion)
    participation
  end

  before { sign_in user }

  it "renders the profile with no seasons" do
    get profile_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Season Medals")
  end

  it "renders the profile with a medalled season and one below bronze" do
    gold = build_season(name: "Gold Season", status: "ended", starts_at: 2.months.ago, ends_at: 1.month.ago)
    rookie = build_season(name: "Rookie Season", status: "active")
    participate(gold, fragments: 130, level: 20, completion: 88)
    participate(rookie, fragments: 4, level: 2, completion: 5)

    get profile_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Gold Season", "Rookie Season")
    expect(response.body).to include("Gold")
    expect(response.body).to include("Level 20 · 88% complete")
  end

  it "renders the achievements page with medals and progress" do
    season = build_season(name: "Medal Season", status: "active")
    participate(season, fragments: 70, level: 12, completion: 40)

    get achievements_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Medal Season")
    expect(response.body).to include("Silver")
    expect(response.body).to include("fragments to Gold")
  end

  it "renders the achievements empty state" do
    get achievements_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No seasons yet")
  end

  # Only Season::ARCHIVE_DEPTH finished seasons stay openable. An older one is
  # still part of the player's record, so it must render — just not as a link
  # that bounces them back to the list with an "archived" alert.
  it "renders a season that has aged out of the archive without linking to it" do
    old = build_season(name: "Ancient Season", status: "ended", starts_at: 2.years.ago, ends_at: 23.months.ago)
    recent = build_season(name: "Recent Season", status: "ended", starts_at: 2.months.ago, ends_at: 1.month.ago)
    participate(old, fragments: 200)
    participate(recent, fragments: 30)

    get profile_path
    expect(response.body).to include("Ancient Season")
    expect(response.body).not_to include(season_path(old))
    expect(response.body).to include(season_path(recent))
  end

  it "renders a season reward badge on the achievements page" do
    season = build_season(status: "active")
    participate(season, fragments: 30)
    badge = Badge.create!(name: "Founder Badge", badge_type: "season", icon: "🏅")
    user.user_badges.create!(badge: badge, earned_at: Time.current)

    get achievements_path
    expect(response.body).to include("Founder Badge")
  end
end
