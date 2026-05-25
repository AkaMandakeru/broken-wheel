# frozen_string_literal: true

class HomeController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def index
    redirect_to challenges_path if user_signed_in?
  end
end
