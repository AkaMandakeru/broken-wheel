# frozen_string_literal: true

module Api
  # A retried POST must never write twice. When the app sends an
  # Idempotency-Key, the first response is stored and replayed for any retry
  # with the same key; the same key with a different body is refused.
  #
  #   idempotent only: [ :create ]
  #
  # Keys are per user, so the actions must require authentication.
  module Idempotent
    extend ActiveSupport::Concern

    HEADER = "Idempotency-Key"

    class_methods do
      def idempotent(**options)
        around_action :with_idempotency_key, **options
      end
    end

    private

    def with_idempotency_key
      key = request.headers[HEADER].to_s.strip
      return yield if key.blank? || current_user.nil?
      return render_error(:bad_request, "invalid_idempotency_key") if key.length > 255

      record = IdempotencyKey.claim(user: current_user, key: key, request_digest: idempotency_digest)

      case record
      in IdempotencyKey::Conflict then render_error :unprocessable_content, "idempotency_key_reused"
      in IdempotencyKey::InProgress then render_error :conflict, "idempotency_key_in_progress"
      in IdempotencyKey if record.completed? then replay(record)
      in IdempotencyKey
        begin
          yield
        rescue Exception # rubocop:disable Lint/RescueException
          # rescue_from renders after this callback unwinds, so the response
          # can't be stored here. Release the key instead: a retry runs again.
          record.destroy
          raise
        end
        record.finish(status: response.status, body: response.body)
      end
    end

    def replay(record)
      response.headers["Idempotent-Replayed"] = "true"
      if record.response_body.nil?
        head record.response_status
      else
        render json: record.response_body, status: record.response_status
      end
    end

    def idempotency_digest
      Digest::SHA256.hexdigest([ request.request_method, request.path, request.raw_post ].join("\n"))
    end
  end
end
