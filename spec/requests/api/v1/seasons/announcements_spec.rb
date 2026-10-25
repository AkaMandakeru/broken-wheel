# frozen_string_literal: true

require "swagger_helper"

RSpec.describe "API v1 season announcement", type: :request do
  let(:user) { build_user }
  let!(:season) { build_season.tap { |s| s.update_columns(announced_at: 1.day.ago) } }

  path "/api/v1/seasons/{season_id}/announcement/dismiss" do
    parameter name: :season_id, in: :path, schema: { type: :integer }

    post "Close the \"new season\" banner for good" do
      tags "Seasons"

      response "204", "dismissed" do
        let(:season_id) { season.id }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        run_test! do
          expect(user.reload.dismissed_season_announcement?(season.id)).to be(true)
          expect(Seasons::Announcement.for(user)).to be_nil
        end
      end

      response "401", "signed out" do
        schema "$ref" => "#/components/schemas/error"
        let(:season_id) { season.id }
        let(:Authorization) { nil }

        run_test!
      end

      response "404", "unknown season" do
        schema "$ref" => "#/components/schemas/error"
        let(:season_id) { 0 }
        let(:Authorization) { "Bearer #{api_sign_in(user).access_token}" }

        run_test!
      end
    end
  end

  it "records the dismissal like the web" do
    allow(SeasonAnalytics).to receive(:track)

    post "/api/v1/seasons/#{season.id}/announcement/dismiss", headers: api_headers(user)

    expect(SeasonAnalytics).to have_received(:track)
      .with(user: user, event: "season_announcement_dismissed", season: season)
  end
end
