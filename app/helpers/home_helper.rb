# frozen_string_literal: true

module HomeHelper
  # True when a real screenshot has been dropped into app/assets/images/<name>.
  # Lets the landing page auto-swap faux mockups for real product screenshots
  # with no code changes — just add the file.
  def screenshot_available?(name)
    return false if name.blank?

    @screenshot_cache ||= {}
    @screenshot_cache.fetch(name) do
      @screenshot_cache[name] = File.exist?(Rails.root.join("app/assets/images", name))
    end
  end
end
