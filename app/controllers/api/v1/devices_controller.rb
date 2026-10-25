# frozen_string_literal: true

module Api
  module V1
    # Push registration for the native apps (Expo push tokens). The app calls
    # create on every launch, which also refreshes last_seen_at, and destroy on
    # sign-out.
    class DevicesController < BaseController
      def create
        device, created = DeviceToken.register!(user: current_user, **device_params.to_h.symbolize_keys)
        render_resource DeviceTokenResource, device, status: created ? :created : :ok
      end

      def destroy
        current_user.device_tokens.find_by!(token: params[:token]).destroy!
        head :no_content
      end

      private

      def device_params
        params.expect(device: [ :platform, :token, :app_version, :locale ])
      end
    end
  end
end
