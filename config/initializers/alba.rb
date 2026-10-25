# frozen_string_literal: true

# JSON resources for the mobile API (app/resources). ActiveSupport's encoder
# keeps times, decimals and BigDecimal coins rendering the same way as the
# rest of Rails.
Alba.backend = :active_support
