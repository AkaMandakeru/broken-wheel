# frozen_string_literal: true

module Api
  # Cursor pagination with Pagy's keyset paginator: `?cursor=&limit=`. The
  # scope must be ordered by columns that end in a unique one (usually `id`),
  # so a cursor stays valid while new rows are inserted.
  #
  #   records, meta = paginate(current_user.workouts.order(workout_date: :desc, id: :desc))
  #   render_collection WorkoutResource, records, meta: meta
  module Paginated
    extend ActiveSupport::Concern

    DEFAULT_LIMIT = 20
    MAX_LIMIT = 100

    # The cursor is JSON, and Rails encodes times to the millisecond while
    # Postgres keeps microseconds. A truncated cutoff skips every row created
    # in the same millisecond as the last one on the page.
    PRESERVE_TIME_PRECISION = ->(attributes) {
      attributes.each { |key, value| attributes[key] = value.utc.iso8601(6) if value.respond_to?(:utc) }
    }

    class InvalidCursor < StandardError; end

    included do
      rescue_from InvalidCursor do
        render_error :bad_request, "invalid_cursor"
      end
    end

    private

    def paginate(scope, limit: DEFAULT_LIMIT)
      # Pagy quietly treats an undecodable cursor as the first page; the app
      # should hear that its cursor is bad instead of looping over page one.
      if params[:cursor].present? && !Pagy::Keyset.decode(params[:cursor].to_s).is_a?(Array)
        raise InvalidCursor, "undecodable cursor"
      end
      pagy, records = pagy(:keyset, scope, limit: limit, client_limit: MAX_LIMIT,
                                          page_key: "cursor", limit_key: "limit",
                                          pre_serialize: PRESERVE_TIME_PRECISION)
      [ records.to_a, { next_cursor: pagy.next } ]
    rescue Pagy::OptionError, Pagy::InternalError, JSON::ParserError, ArgumentError => error
      raise InvalidCursor, error.message
    end
  end
end
