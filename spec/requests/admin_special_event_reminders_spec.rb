# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin special event reminders", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { build_user(admin: true) }
  let(:season) { build_season(starts_at: Date.new(2026, 10, 1), ends_at: Date.new(2026, 10, 31)) }
  let(:event_date) { Date.new(2026, 10, 31) }
  let(:season_challenge) do
    challenge = build_challenge(key: "halloween_run", requirements: [ { metric: "distance_km", target: 7 } ],
                                starts_at: event_date, ends_at: event_date)
    season.season_challenges.create!(challenge: challenge, category: "special", xp_reward: 1000,
                                     starts_at: event_date, ends_at: event_date)
  end

  before { sign_in admin }

  def banner_upload(file: "season_cover.png", content_type: "image/png")
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/#{file}"), content_type)
  end

  it "shows the reminder panel on special challenges" do
    season_challenge

    get admin_season_path(season)

    expect(response.body).to include(I18n.t("admin.seasons.reminders.title"))
    expect(response.body).to include(I18n.t("admin.seasons.reminders.send_test"))
  end

  it "uploads the email banner" do
    patch admin_season_season_challenge_path(season, season_challenge),
          params: { season_challenge: { email_banner: banner_upload } }

    expect(response).to redirect_to(admin_season_path(season))
    expect(season_challenge.reload.email_banner).to be_attached
  end

  it "rejects a banner that is not a picture" do
    patch admin_season_season_challenge_path(season, season_challenge),
          params: { season_challenge: { email_banner: banner_upload(file: "not_an_image.txt", content_type: "text/plain") } }

    expect(flash[:alert]).to be_present
    expect(season_challenge.reload.email_banner).not_to be_attached
  end

  it "removes the banner" do
    season_challenge.email_banner.attach(banner_upload)

    patch admin_season_season_challenge_path(season, season_challenge), params: { remove_email_banner: 1 }

    expect(season_challenge.reload.email_banner).not_to be_attached
  end

  it "sends a test to the admin only, without marking it sent" do
    build_user

    expect {
      post send_test_reminder_admin_season_season_challenge_path(season, season_challenge)
    }.to have_enqueued_mail(EngagementMailer, :special_event_reminder)
      .with(params: { user: admin, season_challenge: season_challenge }, args: []).exactly(:once)

    expect(season_challenge.reload.reminder_sent_at).to be_nil
  end

  it "sends to everyone on demand" do
    build_user

    expect {
      post send_reminder_admin_season_season_challenge_path(season, season_challenge)
    }.to have_enqueued_mail(EngagementMailer, :special_event_reminder).exactly(2).times

    expect(season_challenge.reload.reminder_sent_at).to be_present
  end
end
