# frozen_string_literal: true

# One switch per feature. Rows are created lazily the first time a feature is
# toggled off, so an empty table means "everything on".
class FeatureFlag < ApplicationRecord
  validates :key, presence: true, uniqueness: true, inclusion: { in: ->(_f) { Features.keys } }

  scope :disabled, -> { where(enabled: false) }

  after_commit :clear_cache

  def self.set(key, enabled, actor: nil)
    flag = find_or_initialize_by(key: key.to_s)
    flag.enabled = enabled
    flag.disabled_at = enabled ? nil : Time.current
    flag.disabled_by = enabled ? nil : actor
    flag.save!
    flag
  end

  private

  def clear_cache
    Features.reset_cache
  end
end
