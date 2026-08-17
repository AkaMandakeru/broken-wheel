# frozen_string_literal: true

class HomeController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def index
    return unless user_signed_in?

    # Feature-aware, and never a redirect back to this action: with everything
    # switched off `logged_in_home_path` returns here, and signed-in users see
    # the landing page rather than bouncing between two redirects.
    destination = logged_in_home_path
    redirect_to destination unless destination == root_path
  end
end
