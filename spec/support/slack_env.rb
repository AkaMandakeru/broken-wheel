# frozen_string_literal: true

# Builds an environment with no Slack settings, so a developer whose .env has
# real webhooks configured gets the same result as CI. Without this the specs
# inherit whatever is on the machine and "stays quiet" assertions flip.
module SlackEnvHelper
  def slack_env(**vars)
    cleaned = ENV.to_h.reject { |key, _| key.start_with?("SLACK_") }
    stub_const("ENV", cleaned.merge(vars.transform_keys(&:to_s)))
  end
end

RSpec.configure { |config| config.include SlackEnvHelper }
