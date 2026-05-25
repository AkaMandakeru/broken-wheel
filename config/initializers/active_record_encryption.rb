# frozen_string_literal: true

# Active Record Encryption keys.
#
# Production/staging must provide real keys via Rails credentials, e.g.:
#
#   active_record_encryption:
#     primary_key: ...
#     deterministic_key: ...
#     key_derivation_salt: ...
#
# In development and test we fall back to fixed dummy keys so the app boots
# without requiring `bin/rails db:encryption:init` on every machine.

Rails.application.config.to_prepare do
  config = Rails.application.config.active_record.encryption
  credentials = Rails.application.credentials.active_record_encryption || {}

  config.primary_key         ||= credentials[:primary_key]         || ENV["AR_ENCRYPTION_PRIMARY_KEY"]
  config.deterministic_key   ||= credentials[:deterministic_key]   || ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
  config.key_derivation_salt ||= credentials[:key_derivation_salt] || ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]

  if Rails.env.development? || Rails.env.test?
    config.primary_key         ||= "development_primary_key_change_me_32"
    config.deterministic_key   ||= "development_deterministic_key_32____"
    config.key_derivation_salt ||= "development_key_derivation_salt_32__"
  end
end
