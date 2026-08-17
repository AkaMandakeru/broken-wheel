# frozen_string_literal: true

# The catalogue of switchable features, and the one place that answers
# "is this on?".
#
# Everything in the header menu is here except Profile and Admin: an operator
# who could switch those off would lock themselves out of the screen that turns
# them back on.
#
# A feature with no `feature_flags` row is enabled. Defaulting to on means a new
# entry in this catalogue works immediately, and a wiped or unreachable table
# degrades to a fully working app rather than a blank one.
module Features
  Feature = Struct.new(:key, :icon, :controllers, keyword_init: true) do
    def name = I18n.t("features.#{key}.name", default: key.to_s.humanize)
    def description = I18n.t("features.#{key}.description", default: "")
  end

  # `controllers` are the controller paths guarded when the feature is off, so
  # switching something off closes the URL as well as hiding the link.
  CATALOGUE = [
    Feature.new(key: "challenges",   icon: "fa-solid fa-trophy",          controllers: %w[challenges timeline_posts timeline_post_comments]),
    Feature.new(key: "events",       icon: "fa-solid fa-flag-checkered",  controllers: %w[events event_participations]),
    Feature.new(key: "seasons",      icon: "fa-solid fa-ranking-star",    controllers: %w[seasons]),
    Feature.new(key: "workouts",     icon: "fa-solid fa-dumbbell",        controllers: %w[workouts]),
    Feature.new(key: "achievements", icon: "fa-solid fa-medal",           controllers: %w[achievements]),
    Feature.new(key: "clubs",        icon: "fa-solid fa-users",           controllers: %w[clubs]),
    Feature.new(key: "integrations", icon: "fa-solid fa-plug",            controllers: %w[integrations oauth]),
    Feature.new(key: "support",      icon: "fa-solid fa-life-ring",       controllers: %w[support_tickets support_messages])
  ].freeze

  KEYS = CATALOGUE.map(&:key).freeze

  module_function

  def all = CATALOGUE

  def keys = KEYS

  def find(key) = CATALOGUE.find { |feature| feature.key == key.to_s }

  def exists?(key) = KEYS.include?(key.to_s)

  def enabled?(key)
    return true unless exists?(key)

    !disabled_keys.include?(key.to_s)
  end

  def disabled?(key) = !enabled?(key)

  # The feature that owns a controller path, or nil when it isn't guarded.
  def for_controller(controller_path)
    controller_index[controller_path.to_s]
  end

  # Loaded once per request. The table is tiny, but the nav asks about every
  # feature on every page.
  def disabled_keys
    Current.disabled_feature_keys ||= load_disabled_keys
  end

  def reset_cache
    Current.disabled_feature_keys = nil
  end

  def load_disabled_keys
    FeatureFlag.disabled.pluck(:key).to_set
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    # Before the table exists (migrations, a fresh checkout) everything is on.
    Set.new
  end

  def controller_index
    @controller_index ||= CATALOGUE.each_with_object({}) do |feature, index|
      feature.controllers.each { |path| index[path] = feature }
    end
  end

  private_class_method :load_disabled_keys, :controller_index
end
