# frozen_string_literal: true

class PwaController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  # The service worker is fetched by the browser's registration, not by an XHR
  # and not from a <script> tag. Rails guards JavaScript responses against
  # cross-origin <script> embedding (verify_same_origin_request), which a
  # service worker request trips every time — it raised InvalidCrossOriginRequest
  # and answered 422, so the worker never installed.
  #
  # Skipping is safe here rather than merely convenient: both actions are public,
  # GET-only and read nothing from the session, so there is no CSRF surface. The
  # skip works by never marking the request for same-origin verification in the
  # first place — that flag is set inside verify_authenticity_token.
  skip_forgery_protection

  def manifest
    response.headers["Cache-Control"] = "no-cache"
    render json: {
      name: "Broken Wheels",
      short_name: "Broken Wheels",
      description: I18n.t("pwa.description"),
      start_url: root_path,
      display: "standalone",
      background_color: "#ffffff",
      theme_color: "#FC4C02",
      icons: [
        { src: "/icon.png", sizes: "512x512", type: "image/png", purpose: "any" },
        { src: "/icon.png", sizes: "512x512", type: "image/png", purpose: "maskable" }
      ]
    }
  end

  def service_worker
    render layout: false, content_type: "application/javascript"
  end
end
