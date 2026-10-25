# frozen_string_literal: true

module Api
  # One error shape for the whole API:
  #
  #   { "error": { "code": "validation_failed", "message": "...", "fields": { "email": ["is invalid"] } } }
  #
  # `code` is stable and meant for the app's logic; `message` is localised and
  # meant for the player.
  module ErrorHandling
    extend ActiveSupport::Concern

    included do
      rescue_from ActiveRecord::RecordNotFound do
        render_error :not_found, "not_found"
      end

      rescue_from ActiveRecord::RecordInvalid do |error|
        render_invalid error.record
      end

      rescue_from ActionController::ParameterMissing, ActionController::BadRequest do
        render_error :bad_request, "bad_request"
      end

      # Raised by every `rate_limit` (its default `with:`), so throttled
      # endpoints all answer the same way without repeating a handler.
      rescue_from ActionController::TooManyRequests do
        render_error :too_many_requests, "rate_limited"
      end

      rescue_from ActiveSupport::MessageVerifier::InvalidSignature do
        render_error :unprocessable_content, "invalid_signed_id"
      end
    end

    private

    # rescue_from handlers run outside Api::Localized's around_action, so the
    # request's locale is set again here rather than inherited.
    # `details` adds machine-readable context beside the code, e.g. which
    # feature was switched off. It can't replace `code` or `message`.
    def render_error(status, code, message: nil, fields: nil, **details)
      I18n.with_locale(api_locale) do
        body = { **details, code: code, message: message || I18n.t("api.errors.#{code}") }
        body[:fields] = fields if fields.present?
        render json: { error: body }, status: status
      end
    end

    def render_invalid(record)
      fields = I18n.with_locale(api_locale) do
        record.errors.to_hash(true).transform_values { |messages| messages.map(&:to_s) }
      end
      render_error :unprocessable_content, "validation_failed", fields: fields
    end
  end
end
