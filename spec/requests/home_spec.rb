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
      expect(response.body).to include(I18n.t("home.hero.headline_lead", locale: :en))
      expect(response.body).to include(I18n.t("home.hero.headline_accent", locale: :en))
    end

    it "renders the hero headline in Portuguese" do
      get root_path, params: { locale: "pt" }
      expect(response.body).to include(I18n.t("home.hero.headline_lead", locale: :pt))
      expect(response.body).to include(I18n.t("home.hero.headline_accent", locale: :pt))
    end

    it "shows the sign-up CTA for guests" do
      get root_path, params: { locale: "en" }
      expect(response.body).to include(I18n.t("home.hero.cta_primary", locale: :en))
    end

    it "renders the MandakeruLabs label in the footer" do
      get root_path
      expect(response.body).to include("MandakeruLabs")
    end

    it "renders the feature cards" do
      get root_path, params: { locale: "en" }
      %w[import achievements challenges progress].each do |key|
        expected = ERB::Util.html_escape(I18n.t("home.features.items.#{key}.title", locale: :en))
        expect(response.body).to include(expected)
      end
    end

    it "renders the features section title" do
      get root_path, params: { locale: "en" }
      expect(response.body).to include(I18n.t("home.features.title", locale: :en))
    end
  end
end
