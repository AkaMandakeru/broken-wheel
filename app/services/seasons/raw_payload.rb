# frozen_string_literal: true

module Seasons
  # Reads fields out of a stored provider payload. Strava activities arrive as
  # gem objects during import and as plain hashes when replayed from
  # `workouts.raw_data`, so every accessor must tolerate both.
  module RawPayload
    module_function

    # Hash lookup comes first on purpose: a payload hash `respond_to?(:map)`
    # via Enumerable, so method dispatch would silently return the pairs array
    # instead of the activity's "map" field.
    def field(payload, key)
      if payload.is_a?(Hash)
        payload[key.to_s].nil? ? payload[key.to_sym] : payload[key.to_s]
      elsif payload.respond_to?(key)
        payload.public_send(key)
      elsif payload.respond_to?(:[])
        payload[key] || payload[key.to_s]
      end
    end

    # Always returns UTC. Strava tags `start_date_local` with a "Z" it does not
    # mean — it is a wall clock, not an instant — so converting zones would
    # shift the very value hour-based challenges compare against.
    def time(value)
      return nil if value.blank?

      time = value.respond_to?(:to_time) ? value.to_time : Time.parse(value.to_s)
      time.utc
    rescue ArgumentError, TypeError
      nil
    end

    # Hashing the summary polyline fingerprints a route without storing the track.
    def route_signature(payload)
      map = field(payload, :map)
      return nil if map.blank?

      polyline = field(map, :summary_polyline)
      return nil if polyline.blank?

      Digest::SHA256.hexdigest(polyline)[0, 32]
    end
  end
end
