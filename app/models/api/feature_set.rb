# frozen_string_literal: true

module Api
  # The features the app may show right now, in menu order, and the ones an
  # admin has switched off. `version` changes whenever that split changes; every
  # API response carries it (X-Features-Version), so the app knows to fetch
  # /config again instead of polling it.
  module FeatureSet
    module_function

    def available = Features.all.select { |feature| Features.enabled?(feature.key) }

    def unavailable = Features.all.reject { |feature| Features.enabled?(feature.key) }

    def version
      Digest::SHA256.hexdigest(Features.disabled_keys.sort.join(",")).first(12)
    end
  end
end
