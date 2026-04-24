class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :set_locale

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def set_locale
    locale = session[:locale] || params[:locale] || I18n.default_locale
    I18n.locale = locale
    Rails.logger.info "Set locale to: #{I18n.locale}, session: #{session[:locale]}, params: #{params[:locale]}"
  end
end
