# frozen_string_literal: true

module Slack
  # Every Slack setting comes from the environment — no URLs, channels or IDs
  # live in the repo, because an incoming-webhook URL is a credential: anyone
  # holding it can post to the channel.
  #
  #   SLACK_WEBHOOK_URL                    default incoming webhook
  #   SLACK_WEBHOOK_URL_USER_REGISTERED    optional per-event override
  #   SLACK_WEBHOOK_URL_PREMIUM_GRANTED    "
  #   SLACK_WEBHOOK_URL_WORKOUT_IMPORTED   "
  #   SLACK_CHANNEL                        optional channel override (#ops)
  #   SLACK_USERNAME                       optional bot name
  #   SLACK_ENVIRONMENT                    which deployment this is — see below
  #   SLACK_NOTIFICATIONS_ENABLED          "true" to allow outside production
  #   SLACK_TIME_ZONE                      timestamp zone (default America/Sao_Paulo)
  #
  # Off everywhere but production unless told otherwise, so a developer's
  # machine never posts to the team's channel by accident.
  module Config
    # A staging deployment normally runs with RAILS_ENV=production, so Rails.env
    # cannot tell staging from the real thing. SLACK_ENVIRONMENT names the
    # deployment explicitly, which does two jobs: it tags the message so nobody
    # mistakes a test for a real signup, and setting it is itself the opt-in
    # that turns notifications on outside production.
    ENVIRONMENT_TAGS = {
      "development" => "DEV",
      "dev" => "DEV",
      "staging" => "STG",
      "stg" => "STG",
      "test" => "TEST",
      "qa" => "QA"
    }.freeze

    PRODUCTION_NAMES = %w[production prod live].freeze

    module_function

    # The deployment's own name, falling back to the Rails environment.
    def environment
      (ENV["SLACK_ENVIRONMENT"].presence || Rails.env).to_s.strip.downcase
    end

    def production?
      PRODUCTION_NAMES.include?(environment)
    end

    # "DEV", "STG"… or nil in production, where a tag would just be noise.
    def environment_tag
      return nil if production?

      ENVIRONMENT_TAGS.fetch(environment) { environment.upcase[0, 10] }
    end

    def enabled?
      return false unless any_webhook?
      return true if production?

      # Either explicitly labelling this deployment, or the plain boolean.
      ENV["SLACK_ENVIRONMENT"].present? || forced_on?
    end

    def forced_on?
      ActiveModel::Type::Boolean.new.cast(ENV["SLACK_NOTIFICATIONS_ENABLED"]).present?
    end

    def any_webhook?
      return true if ENV["SLACK_WEBHOOK_URL"].present?

      Event.keys.any? { |key| ENV["SLACK_WEBHOOK_URL_#{key.to_s.upcase}"].present? }
    end

    # A per-event webhook when one is configured, otherwise the default.
    def webhook_url_for(event_key)
      per_event = ENV["SLACK_WEBHOOK_URL_#{event_key.to_s.upcase}"] if event_key
      per_event.presence || ENV["SLACK_WEBHOOK_URL"].presence
    end

    def channel
      ENV["SLACK_CHANNEL"].presence
    end

    # Nil unless explicitly set. Incoming webhooks ignore a username override
    # without the chat:write.customize scope, so the default is to send nothing
    # and let the Slack app's own name and icon apply.
    def username
      ENV["SLACK_USERNAME"].presence
    end

    def time_zone
      ENV["SLACK_TIME_ZONE"].presence || "America/Sao_Paulo"
    end

    # What the status task and any diagnostics view need, without ever exposing
    # the URL itself.
    def status
      {
        enabled: enabled?,
        environment: environment,
        rails_env: Rails.env.to_s,
        tag: environment_tag,
        production: production?,
        forced_on: forced_on?,
        default_webhook: ENV["SLACK_WEBHOOK_URL"].present?,
        per_event_webhooks: Event.keys.select { |key| ENV["SLACK_WEBHOOK_URL_#{key.to_s.upcase}"].present? },
        channel: channel
      }
    end
  end
end
