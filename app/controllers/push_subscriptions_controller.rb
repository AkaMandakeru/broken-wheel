# frozen_string_literal: true

class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!

  # Store (or refresh) the browser's push subscription for the current user.
  def create
    subscription = PushSubscription.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    subscription.assign_attributes(
      user: current_user,
      p256dh_key: subscription_params.dig(:keys, :p256dh),
      auth_key: subscription_params.dig(:keys, :auth),
      user_agent: request.user_agent
    )

    if subscription.save
      head :created
    else
      render json: { errors: subscription.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # Remove a subscription (e.g. when the user turns notifications off).
  def destroy
    current_user.push_subscriptions.where(endpoint: params[:endpoint]).destroy_all
    head :no_content
  end

  private

  def subscription_params
    params.require(:subscription).permit(:endpoint, keys: [ :p256dh, :auth ])
  end
end
