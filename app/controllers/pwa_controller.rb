# frozen_string_literal: true

class PwaController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def manifest
    response.headers["Cache-Control"] = "no-cache"
    render json: {
      name: "Sports Communities",
      short_name: "Sports",
      description: "Sports challenges and communities",
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
