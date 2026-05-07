class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :set_locale

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def set_locale
    requested = (params[:locale] || session[:locale] || I18n.default_locale).to_sym
    I18n.locale = I18n.available_locales.include?(requested) ? requested : I18n.default_locale
  end
end
