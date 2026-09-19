# frozen_string_literal: true

require "rails_helper"

# Both endpoints are fetched by the browser itself, not by the app's own
# JavaScript, so neither carries a CSRF token or an XHR header.
RSpec.describe "PWA", type: :request do
  describe "GET /service-worker" do
    # Rails guards JavaScript responses against cross-origin <script> embedding.
    # A service worker registration is neither an XHR nor a <script> tag, so the
    # guard fired on every fetch and answered 422 — the worker never installed.
    it "serves the worker instead of refusing it as a cross-origin script" do
      get pwa_service_worker_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to match(%r{\A(?:text|application)/javascript})
    end

    # What a browser actually sends when registering a worker.
    it "serves it for the browser's own Accept: */* request" do
      get pwa_service_worker_path, headers: { "Accept" => "*/*" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_present
    end

    it "serves it to a signed-out visitor" do
      get pwa_service_worker_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to be_present
    end

    it "serves it to a signed-in user too" do
      sign_in build_user

      get pwa_service_worker_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /manifest" do
    it "serves the manifest as JSON" do
      get pwa_manifest_path(format: :json)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("Broken Wheels")
      expect(response.parsed_body["start_url"]).to eq(root_path)
    end
  end
end
