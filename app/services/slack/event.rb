# frozen_string_literal: true

module Slack
  # The catalogue of things worth telling the team about.
  #
  # Adding an event here is all it takes to make it routable to its own webhook
  # via SLACK_WEBHOOK_URL_<KEY>.
  module Event
    Definition = Struct.new(:key, :emoji, :label, keyword_init: true)

    ALL = [
      Definition.new(key: :user_registered,  emoji: "🎉", label: "New user registered"),
      Definition.new(key: :premium_granted,  emoji: "⭐", label: "Premium pass granted"),
      Definition.new(key: :workout_imported, emoji: "🏃", label: "Workout imported")
    ].freeze

    module_function

    def all = ALL

    def keys = ALL.map(&:key)

    def find(key) = ALL.find { |event| event.key == key.to_sym }

    def exists?(key) = keys.include?(key.to_sym)
  end
end
