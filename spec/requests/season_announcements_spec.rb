# frozen_string_literal: true

require "rails_helper"

# Push only reaches players who granted permission, so the in-app banner is what
# actually tells everyone else that a season has opened.
RSpec.describe "Season announcements", type: :request do
  let(:user) { build_user }
  let!(:season) do
    build_season(status: "active", name: "Opening Season").tap do |s|
      s.update_columns(announced_at: 1.hour.ago)
    end
  end

  describe "the banner" do
    it "shows on any page to a signed-in user" do
      sign_in user

      get challenges_path

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.announcement.eyebrow")))
      expect(response.body).to include("Opening Season")
    end

    it "is not shown to a signed-out visitor" do
      get root_path

      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("seasons.announcement.eyebrow")))
    end

    it "links through to the season" do
      sign_in user

      get challenges_path

      expect(response.body).to include(season_path(season))
    end

    # The CTA carries its origin so the click can be counted without a redirect
    # hop. There is deliberately no "banner shown" event — it renders on every
    # page and would drown the funnel it is meant to measure.
    it "tags the CTA with where the click came from" do
      sign_in user

      get challenges_path

      expect(response.body).to include(season_path(season, from: "announcement"))
    end
  end

  describe "measuring it" do
    before { sign_in user }

    it "records a click arriving from the banner" do
      get season_path(season, from: "announcement")

      event = AnalyticsEvent.find_by(user: user, event_name: "season_announcement_clicked")
      expect(event.properties).to include("season_key" => season.key)
    end

    it "records nothing for an ordinary visit to the season" do
      get season_path(season)

      expect(AnalyticsEvent.where(event_name: "season_announcement_clicked")).to be_empty
    end

    it "records the dismissal" do
      post season_dismiss_announcement_path(season)

      event = AnalyticsEvent.find_by(user: user, event_name: "season_announcement_dismissed")
      expect(event.properties).to include("season_key" => season.key)
    end
  end

  describe "dismissing it" do
    before { sign_in user }

    it "stops showing it to that user" do
      post season_dismiss_announcement_path(season)

      get challenges_path
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("seasons.announcement.eyebrow")))
    end

    it "answers JSON for the in-page dismissal" do
      post season_dismiss_announcement_path(season), as: :json

      expect(response).to have_http_status(:no_content)
    end

    it "redirects back for a plain form post" do
      post season_dismiss_announcement_path(season), headers: { "HTTP_REFERER" => challenges_url }

      expect(response).to redirect_to(challenges_url)
    end

    it "leaves other users' banners alone" do
      post season_dismiss_announcement_path(season)

      sign_out user
      sign_in build_user
      get challenges_path

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("seasons.announcement.eyebrow")))
    end

    it "requires signing in" do
      sign_out user

      post season_dismiss_announcement_path(season)

      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "the admin control" do
    let(:admin) { build_user(admin: true) }

    before { sign_in admin }

    it "shows when the season was announced and how far push reaches" do
      get admin_season_path(season)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.seasons.announce.title")))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.seasons.announce.resend")))
    end

    it "offers a first send for a season never announced" do
      fresh = build_season(status: "active")
      fresh.update_columns(announced_at: nil)

      get admin_season_path(fresh)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.seasons.announce.send")))
    end

    it "queues the announcement" do
      expect { post announce_admin_season_path(season) }
        .to have_enqueued_job(AnnounceSeasonJob)

      expect(response).to redirect_to(admin_season_path(season))
    end

    it "keeps non-admins out" do
      sign_out admin
      sign_in user

      post announce_admin_season_path(season)

      expect(response).to redirect_to(root_path)
    end
  end
end
