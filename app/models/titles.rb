# frozen_string_literal: true

# Read-only registry for the profile titles defined in config/titles.yml.
# Titles are not stored in the database — users keep the keys they've earned in
# a JSONB array (see User#titles). Add new titles by editing config/titles.yml.
module Titles
  CONFIG_PATH = Rails.root.join("config", "titles.yml")

  class << self
    # { rookie: { default: true, name: { en: "Rookie", pt: "Iniciante" } }, ... }
    def catalog
      # Reload on every call in development so edits to titles.yml show up
      # without a restart; memoize everywhere else.
      Rails.env.development? ? load_catalog : (@catalog ||= load_catalog)
    end

    def keys
      catalog.keys
    end

    def exists?(key)
      key.present? && catalog.key?(key.to_sym)
    end

    # Keys flagged `default: true` — auto-granted to every user.
    def defaults
      catalog.select { |_key, attrs| attrs[:default] }.keys
    end

    # Localized display label, falling back to English then a humanized key.
    def label(key, locale: I18n.locale)
      attrs = catalog[key.to_sym]
      return key.to_s.humanize if attrs.nil?

      names = attrs[:name] || {}
      names[locale.to_sym] || names[:en] || key.to_s.humanize
    end

    private

    def load_catalog
      YAML.safe_load_file(CONFIG_PATH, aliases: true).to_h.deep_symbolize_keys
    end
  end
end
