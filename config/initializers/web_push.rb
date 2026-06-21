# frozen_string_literal: true

# VAPID credentials for Web Push. Generate a keypair once with:
#   ruby -rweb-push -e 'p WebPush.generate_key.then { |k| [k.public_key, k.private_key] }'
# and set VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY / VAPID_SUBJECT in the environment
# (already in .env for development).
Rails.application.config.x.web_push = {
  public_key:  ENV["VAPID_PUBLIC_KEY"],
  private_key: ENV["VAPID_PRIVATE_KEY"],
  subject:     ENV.fetch("VAPID_SUBJECT", "mailto:support@example.com")
}
