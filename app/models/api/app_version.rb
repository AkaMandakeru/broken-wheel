# frozen_string_literal: true

module Api
  # The oldest mobile build still allowed to talk to the API, from
  # MOBILE_MIN_SUPPORTED_VERSION ("1.4.0"). Unset means every build is fine.
  module AppVersion
    module_function

    def minimum = ENV["MOBILE_MIN_SUPPORTED_VERSION"].presence

    def unsupported?(version)
      return false if minimum.nil? || !Gem::Version.correct?(version) || !Gem::Version.correct?(minimum)

      Gem::Version.new(version) < Gem::Version.new(minimum)
    end
  end
end
