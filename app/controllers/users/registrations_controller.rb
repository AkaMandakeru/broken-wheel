# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  before_action :configure_sign_up_params, only: [ :create ]
  before_action :configure_account_update_params, only: [ :update ]

  # Devise's own destroy is a bare `resource.destroy`, which the foreign keys
  # on workouts, clubs, badges… refuse. Accounts::Deletion knows the order.
  def destroy
    Accounts::Deletion.call(resource)
    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    set_flash_message! :notice, :destroyed
    yield resource if block_given?
    respond_with_navigational(resource) do
      redirect_to after_sign_out_path_for(resource_name), status: Devise.responder.redirect_status
    end
  end

  protected

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :first_name, :last_name, :nickname, :avatar ])
  end

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [ :first_name, :last_name, :nickname, :avatar ])
  end

  def after_sign_up_path_for(resource)
    Accounts::Registration.announce(resource)
    logged_in_home_path
  end
end
