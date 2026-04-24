class LocalesController < ApplicationController
  def switch
    locale = params[:locale].to_s.strip.to_sym
    
    # Define available locales
    available_locales = [:en, :pt]
    
    # Check if the locale is available, fallback to default
    if available_locales.include?(locale)
      session[:locale] = locale
      Rails.logger.info "Locale set to: #{locale}, session[:locale] = #{session[:locale]}"
    else
      session[:locale] = I18n.default_locale
      Rails.logger.info "Invalid locale #{locale}, falling back to: #{I18n.default_locale}"
    end
    
    # Redirect back or to root path
    redirect_back(fallback_location: root_path)
  end
end
