class LocalesController < ApplicationController
  def switch
    requested = params[:locale].to_s.strip.to_sym
    session[:locale] = I18n.available_locales.include?(requested) ? requested : I18n.default_locale
    redirect_back(fallback_location: root_path)
  end
end
