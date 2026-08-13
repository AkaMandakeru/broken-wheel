# frozen_string_literal: true

require "rails_helper"

# The season picture was uploadable and previewed in admin, but no public view
# ever rendered it.
RSpec.describe "Season pictures", type: :request do
  include SeasonsHelper

  let(:season) { build_season(name: "Pictured Season") }

  def attach_cover(record = season)
    record.image.attach(
      io: Rails.root.join("spec/fixtures/files/season_cover.png").open,
      filename: "season_cover.png",
      content_type: "image/png"
    )
    record
  end

  describe "the season page" do
    it "renders the picture as a banner when one is attached" do
      attach_cover

      get season_path(season)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/rails/active_storage")
      expect(response.body).to include(%(alt="Pictured Season"))
    end

    # The title moves onto the image, so it must still appear exactly once.
    it "shows the name once, over the picture" do
      attach_cover
      season.update!(slogan: "Built to last")

      get season_path(season)

      expect(response.body.scan(/<h1[^>]*>\s*Pictured Season\s*<\/h1>/).size).to eq(1)
      expect(response.body).to include("Built to last")
    end

    it "falls back to the theme gradient when there is no picture" do
      get season_path(season)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("/rails/active_storage")
      expect(response.body).to include(season_theme_classes(season.theme))
    end
  end

  describe "the seasons index" do
    it "shows a cover on the active season and a thumbnail on past ones" do
      attach_cover
      past = attach_cover(build_season(name: "Past Season", status: "ended"))

      get seasons_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(alt="Pictured Season"))
      expect(response.body).to include(%(alt="#{past.name}"))
    end

    it "renders seasons without a picture too" do
      build_season(name: "Plain Season")

      get seasons_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Plain Season")
    end
  end

  describe "what may be uploaded" do
    # The picture is now public, so a bad file should be refused at the form
    # rather than discovered when the page renders.
    it "rejects a file that is not an image" do
      season.image.attach(
        io: Rails.root.join("spec/fixtures/files/not_an_image.txt").open,
        filename: "not_an_image.txt",
        content_type: "text/plain"
      )

      expect(season).not_to be_valid
      expect(season.errors[:image].join).to match(/image/i)
    end

    it "rejects a picture over the size limit" do
      attach_cover
      allow(season.image.blob).to receive(:byte_size).and_return(Season::MAX_IMAGE_BYTES + 1)

      expect(season).not_to be_valid
      expect(season.errors[:image].join).to match(/smaller/i)
    end

    it "accepts a normal picture" do
      attach_cover

      expect(season).to be_valid
    end
  end

  describe "SeasonsHelper#season_image_source" do
    it "returns nil when nothing is attached" do
      expect(season_image_source(season, resize: [ 100, 100 ])).to be_nil
    end

    it "returns nil for a nil season" do
      expect(season_image_source(nil, resize: [ 100, 100 ])).to be_nil
    end

    it "returns a variant for an attached picture" do
      attach_cover

      expect(season_image_source(season, resize: [ 100, 100 ])).to be_present
    end
  end
end
