require "ipaddr"

class ApplicationController < ActionController::Base

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :set_locale

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  COUNTRY_LOCALE = { "BR" => :pt }.freeze
  private_constant :COUNTRY_LOCALE

  def set_locale
    requested =
      if params[:locale].present?
        params[:locale]
      else
        session[:locale] ||= detect_user_locale
      end
    I18n.locale = safe_locale(requested)
  end

  private

  def safe_locale(value)
    symbol = value.to_s.strip.to_sym
    I18n.available_locales.include?(symbol) ? symbol : I18n.default_locale
  end

  def detect_user_locale
    locale_from_ip || locale_from_accept_language || I18n.default_locale
  end

  def locale_from_ip
    ip = request.remote_ip
    return nil if ip.blank? || private_or_loopback?(ip)

    country_code = Rails.cache.fetch(["geo-country", ip], expires_in: 1.day) do
      result = Geocoder.search(ip).first
      result&.country_code.to_s.upcase.presence
    end
    COUNTRY_LOCALE[country_code]
  rescue StandardError => e
    Rails.logger.warn("IP-based locale detection failed for #{request.remote_ip}: #{e.class}: #{e.message}")
    nil
  end

  def locale_from_accept_language
    header = request.env["HTTP_ACCEPT_LANGUAGE"]
    return nil if header.blank?

    primary_tag = header.split(",").first.to_s.split(";").first.to_s.split("-").first.strip.downcase
    return nil if primary_tag.blank?

    symbol = primary_tag.to_sym
    I18n.available_locales.include?(symbol) ? symbol : nil
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || logged_in_home_path
  end

  # Signed-in users land on the active season (or the seasons index if none).
  def logged_in_home_path
    active_season = Season.active.by_recent.first
    active_season ? season_path(active_season) : seasons_path
  end
  helper_method :logged_in_home_path

  def private_or_loopback?(ip)
    addr = IPAddr.new(ip)
    addr.loopback? || addr.private?
  rescue StandardError
    true
  end
end
