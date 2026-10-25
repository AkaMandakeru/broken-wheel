# frozen_string_literal: true

# Emails that bring players back to the app. Every one of them carries a
# one-click unsubscribe — Gmail and Yahoo require it for bulk mail, and the
# opt-out is checked before anything is queued (User.reachable_by_email).
class EngagementMailer < ApplicationMailer
  # Wide enough for a retina 600px email column, small enough to keep the
  # message well under the size where clients start clipping it.
  BANNER_SIZE = [ 1200, 600 ].freeze

  def special_event_reminder
    @user = params[:user]
    @season_challenge = params[:season_challenge]
    @season = @season_challenge.season
    @challenge = @season_challenge.challenge
    @event_date = @season_challenge.event_date
    @days_left = [ (@event_date - @season.current_date).to_i, 0 ].max if @event_date

    I18n.with_locale(@user.email_locale) do
      @banner_filename = attach_banner(@season_challenge.email_banner_source)
      add_unsubscribe_headers

      mail(to: @user.email, subject: t(".subject", title: @challenge.display_title))
    end
  end

  private

  # Inline (CID) rather than a link: the picture travels with the message, so it
  # shows without depending on a storage URL that is signed and expires within
  # minutes. Returns the filename the template references, or nil.
  #
  # Photos stay JPEG; everything else becomes PNG, since several clients
  # (Outlook among them) do not render WEBP.
  def attach_banner(attachment)
    return nil unless attachment&.attached?

    jpeg = attachment.blob.content_type == "image/jpeg"
    filename = jpeg ? "banner.jpg" : "banner.png"
    data =
      if attachment.variable?
        attachment.variant(resize_to_limit: BANNER_SIZE, format: jpeg ? :jpeg : :png).processed.download
      else
        attachment.blob.download
      end

    attachments.inline[filename] = { mime_type: jpeg ? "image/jpeg" : "image/png", content: data }
    filename
  end

  def add_unsubscribe_headers
    @unsubscribe_url = email_unsubscribe_url(token: @user.generate_token_for(:email_unsubscribe))
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
  end
end
