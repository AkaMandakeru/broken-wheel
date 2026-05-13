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
      expect(response.body).to include(I18n.t("home.hero.headline", locale: :en))
    end

    it "renders the hero headline in Portuguese" do
      get root_path, params: { locale: "pt" }
      expect(response.body).to include(I18n.t("home.hero.headline", locale: :pt))
    end

    it "shows the sign-up CTA for guests" do
      get root_path, params: { locale: "en" }
      expect(response.body).to include(I18n.t("home.hero.cta_primary", locale: :en))
    end

    it "renders the MandakeruLabs label in the footer" do
      get root_path
      expect(response.body).to include("MandakeruLabs")
    end

    it "renders all four feature cards" do
      get root_path, params: { locale: "en" }
      %w[challenges tracking achievements clubs].each do |key|
        expected = ERB::Util.html_escape(I18n.t("home.features.#{key}.title", locale: :en))
        expect(response.body).to include(expected)
      end
    end

    it "renders the testimonials section" do
      get root_path, params: { locale: "en" }
      expect(response.body).to include(I18n.t("home.testimonials.title", locale: :en))
      expect(response.body).to include("Mariana Souza")
    end
  end
end
