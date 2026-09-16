# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Home", type: :request do
  describe "GET /" do
    it "returns success" do
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the hero headline in English" do
      get root_path, params: { locale: "en" }
      expect(response.body).to include(I18n.t("home.hero.title_lead", locale: :en))
      expect(response.body).to include(I18n.t("home.hero.title_accent", locale: :en))
    end

    it "renders the hero headline in Portuguese" do
      get root_path, params: { locale: "pt" }
      expect(response.body).to include(I18n.t("home.hero.title_lead", locale: :pt))
      expect(response.body).to include(I18n.t("home.hero.title_accent", locale: :pt))
    end

    it "shows the sign-up CTA for guests" do
      get root_path, params: { locale: "en" }
      expect(response.body).to include(I18n.t("home.hero.cta_primary", locale: :en))
    end

    it "renders the MandakeruLabs label in the footer" do
      get root_path
      expect(response.body).to include("MandakeruLabs")
    end

    it "renders the three how-it-works steps" do
      get root_path, params: { locale: "en" }
      %w[connect progress compete].each do |step|
        expected = ERB::Util.html_escape(I18n.t("home.how.steps.#{step}.title", locale: :en))
        expect(response.body).to include(expected)
      end
    end

    it "renders the how-it-works section title" do
      get root_path, params: { locale: "en" }
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("home.how.title", locale: :en)))
    end

    # The four assertions above are only worth anything while they name keys the
    # page actually renders. They previously pointed at home.hero.headline_* and
    # home.features.*, which no longer exist anywhere in the app.
    it "asserts against keys that exist in both locales" do
      %w[hero.title_lead hero.title_accent how.title].each do |key|
        %i[en pt].each do |locale|
          expect(I18n.exists?("home.#{key}", locale)).to be(true), "home.#{key} missing in #{locale}"
        end
      end
    end
  end
end
