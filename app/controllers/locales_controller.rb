class LocalesController < ApplicationController
  def switch
    session[:locale] = safe_locale(params[:locale])
    redirect_back(fallback_location: root_path)
  end
end
