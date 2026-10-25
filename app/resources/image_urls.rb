# frozen_string_literal: true

# Long-lived image URLs for API responses, served through the CDN when
# CDN_HOST is set (the `cdn_image` route in config/routes.rb proxies through
# Active Storage, and the CDN caches each original and variant once).
#
#   ImageUrls.url(user.avatar, :thumb)   # => "https://cdn…/rails/active_storage/representations/proxy/…"
#   ImageUrls.urls(user.avatar, :thumb, :medium)
#   # => { "original" => "…", "thumb" => "…", "medium" => "…" }
module ImageUrls
  module_function

  def url(attachment, variant = nil)
    return nil unless attachment.respond_to?(:attached?) ? attachment.attached? : attachment.present?

    target = variant && attachment.variable? ? attachment.variant(variant) : attachment
    Rails.application.routes.url_helpers.cdn_image_url(target, **url_options)
  end

  def urls(attachment, *variants)
    return nil unless attachment.respond_to?(:attached?) ? attachment.attached? : attachment.present?

    { "original" => url(attachment) }.merge(variants.to_h { |name| [ name.to_s, url(attachment, name) ] })
  end

  # The request's host when there is no CDN (development, tests).
  def url_options
    ActiveStorage::Current.url_options.presence || { host: ENV.fetch("APP_HOST", "localhost"), protocol: "https" }
  end
end
