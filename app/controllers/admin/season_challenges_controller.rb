# frozen_string_literal: true

module Admin
  class SeasonChallengesController < BaseController
    before_action :load_season
    before_action :load_season_challenge, only: [ :update, :send_test_reminder, :send_reminder ]

    def create
      season_challenge = @season.season_challenges.new(season_challenge_params)
      if season_challenge.save
        redirect_to admin_season_path(@season), notice: t("admin.flashes.season_challenges.added")
      else
        redirect_to admin_season_path(@season), alert: season_challenge.errors.full_messages.to_sentence
      end
    end

    # Only the email banner is edited after creation.
    def update
      if params[:remove_email_banner].present?
        @season_challenge.email_banner.purge
        return redirect_to admin_season_path(@season), notice: t("admin.flashes.season_challenges.banner_removed")
      end

      if @season_challenge.update(params.fetch(:season_challenge, {}).permit(:email_banner))
        redirect_to admin_season_path(@season), notice: t("admin.flashes.season_challenges.banner_saved")
      else
        redirect_to admin_season_path(@season), alert: @season_challenge.errors.full_messages.to_sentence
      end
    end

    def destroy
      @season.season_challenges.find_by(id: params[:id])&.destroy
      redirect_to admin_season_path(@season), notice: t("admin.flashes.season_challenges.removed")
    end

    # Sends the reminder to the admin alone, so the banner and copy can be
    # checked in a real inbox before everyone gets it. Doesn't count as sent.
    def send_test_reminder
      EngagementMailer.with(user: current_user, season_challenge: @season_challenge)
                      .special_event_reminder.deliver_later
      redirect_to admin_season_path(@season), notice: t("admin.flashes.season_challenges.test_sent", email: current_user.email)
    end

    # Sends to everyone now, without waiting for the schedule — or again, when
    # it already went out.
    def send_reminder
      count = SpecialEventReminder.call(@season_challenge, force: true)
      if count
        redirect_to admin_season_path(@season), notice: t("admin.flashes.season_challenges.reminder_sent", count: count)
      else
        redirect_to admin_season_path(@season), alert: t("admin.flashes.season_challenges.reminder_not_sent")
      end
    end

    private

    def load_season
      @season = Season.find(params[:season_id])
    end

    def load_season_challenge
      @season_challenge = @season.season_challenges.find(params[:id])
    end

    def season_challenge_params
      params.require(:season_challenge).permit(:challenge_id, :position, :required, :xp_reward,
                                                :category, :unlock_level, :coin_reward,
                                                :fragment_reward, :week_index)
    end
  end
end
