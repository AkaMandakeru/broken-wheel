# frozen_string_literal: true

# The unsubscribe link in every engagement email. The signed token is the
# credential, so none of this needs a signed-in user.
#
# GET only shows the page: mail scanners and link previewers fetch every link
# in a message, and that must never unsubscribe anyone. The actual opt-out is a
# POST — from the button here, or straight from the mail client through the
# one-click List-Unsubscribe-Post header (RFC 8058), which carries no CSRF token.
class EmailSubscriptionsController < ApplicationController
  skip_forgery_protection only: :create

  before_action :load_user

  def show
  end

  def create
    @user.unsubscribe_from_emails!
    # Mail clients post "List-Unsubscribe=One-Click" and expect a plain 2xx.
    return head :ok if params["List-Unsubscribe"] == "One-Click"

    redirect_to email_unsubscribe_path(token: params[:token]), notice: t("flashes.email_subscriptions.unsubscribed")
  end

  def destroy
    @user.resubscribe_to_emails!
    redirect_to email_unsubscribe_path(token: params[:token]), notice: t("flashes.email_subscriptions.resubscribed")
  end

  private

  def load_user
    @user = User.find_by_token_for(:email_unsubscribe, params[:token])
    render :invalid, status: :not_found unless @user
  end
end
