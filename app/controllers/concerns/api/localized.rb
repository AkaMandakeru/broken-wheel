# frozen_string_literal: true

module Api
  # The app sends its own language in Accept-Language. Without one, the
  # player's remembered locale (the one emails go out in) is used.
  module Localized
    extend ActiveSupport::Concern

    included do
      around_action :switch_locale
    end

    private

    def switch_locale(&action)
      I18n.with_locale(api_locale, &action)
    end

    # Memoised, because errors are rendered by rescue_from handlers, which run
    # after the around_action has already unwound — see Api::ErrorHandling.
    def api_locale
      @api_locale ||= header_locale || remembered_locale || I18n.default_locale
    end

    def header_locale
      header = request.headers["Accept-Language"].to_s
      return nil if header.blank?

      header.split(",").each do |entry|
        tag = entry.split(";").first.to_s.strip.split("-").first.to_s.downcase
        return tag.to_sym if I18n.available_locales.map(&:to_s).include?(tag)
      end
      nil
    end

    def remembered_locale
      resume_session&.user&.email_locale
    end
  end
end
