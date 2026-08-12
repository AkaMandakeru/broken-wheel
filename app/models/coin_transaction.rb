# frozen_string_literal: true

# Append-only ledger for the coin economy. `users.coins` is a cached sum of
# these rows, so a balance can always be rebuilt and never drifts silently.
class CoinTransaction < ApplicationRecord
  belongs_to :user

  validates :amount, numericality: { other_than: 0 }
  validates :reason, :reason_key, presence: true

  scope :credits, -> { where(amount: 1..) }
  scope :debits, -> { where(amount: ..-1) }
end
