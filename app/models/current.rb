# frozen_string_literal: true

# Per-request state. Rails resets this between requests and between jobs, so
# nothing leaks from one to the next.
class Current < ActiveSupport::CurrentAttributes
  # Feature flags are read for every nav item on every page; caching the lookup
  # here keeps it to one query per request.
  attribute :disabled_feature_keys
end
