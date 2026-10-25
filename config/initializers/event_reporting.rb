# frozen_string_literal: true

# Structured events (Rails.event, Rails 8.1) as one JSON log line each, so the
# log drain can search them by name, user or request id. API controllers emit
# them through Api::Events#track_event.
class JsonLogEventSubscriber
  def emit(event)
    Rails.logger.info(
      { event: event[:name], payload: event[:payload], context: event[:context], tags: event[:tags] }.compact_blank.to_json
    )
  end
end

Rails.application.config.after_initialize do
  Rails.event.subscribe(JsonLogEventSubscriber.new) unless Rails.env.test?
end
