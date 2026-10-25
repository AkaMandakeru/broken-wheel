# frozen_string_literal: true

module Api
  module V1
    # The signed-in player's own account: profile, preferences, stats, and
    # closing the account. Edits go through the same User validations as the
    # web's profile form (an unearned title is refused there, not here).
    class MeController < BaseController
      def show
        render_resource MeResource, current_user
      end

      def update
        user = current_user
        attributes = me_params
        locale = attributes.delete(:locale)
        return render_error(:unprocessable_content, "validation_failed", fields: { locale: [ I18n.t("api.profile.unsupported_locale") ] }) if locale && !supported_locale?(locale)

        user.assign_attributes(attributes.except(:avatar))
        assign_avatar(user, attributes) if attributes.key?(:avatar)
        return render_invalid(user) unless user.save

        user.remember_locale(locale) if locale
        track_event "api.profile.updated", fields: attributes.keys
        render_resource MeResource, user
      rescue UploadedImage::Invalid => error
        render_error :unprocessable_content, "invalid_upload", fields: { error.attribute => [ error.message ] }
      end

      def stats
        render_resource ProfileStatsResource, Profiles::Stats.new(current_user)
      end

      # Answers before the rows are gone: the player is signed out and locked
      # out now, and Accounts::DeletionJob removes the account shortly after.
      def destroy
        Accounts::Deletion.request(current_user)
        track_event "api.account.deletion_requested"
        head :accepted
      end

      private

      def me_params
        params.expect(user: [ *User::PROFILE_ATTRIBUTES, :avatar, :locale, sports: [] ])
      end

      # `avatar: null` removes the picture; a signed id from POST /uploads
      # (purpose "avatar") replaces it.
      def assign_avatar(user, attributes)
        if attributes[:avatar].blank?
          user.avatar = nil
        else
          user.avatar = UploadedImage.find!(attributes[:avatar], user: user, purpose: "avatar")
        end
      end

      def supported_locale?(locale)
        I18n.available_locales.map(&:to_s).include?(locale.to_s)
      end
    end
  end
end
