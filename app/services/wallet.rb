# frozen_string_literal: true

# Coin balance operations. Every movement writes a ledger row first; the unique
# index on (user_id, reason_key) makes granting the same reward twice a no-op
# instead of free currency.
module Wallet
  class InsufficientFunds < StandardError; end

  module_function

  def credit(user, amount:, reason:, reason_key:, metadata: {})
    return false if amount.to_i <= 0

    record(user, amount: amount.to_i, reason: reason, reason_key: reason_key, metadata: metadata)
  end

  def debit(user, amount:, reason:, reason_key:, metadata: {})
    return false if amount.to_i <= 0
    raise InsufficientFunds if user.coins < amount.to_i

    record(user, amount: -amount.to_i, reason: reason, reason_key: reason_key, metadata: metadata)
  end

  # Recomputes the cached balance from the ledger. Safe to run at any time.
  def rebuild_balance(user)
    total = user.coin_transactions.sum(:amount)
    user.update_column(:coins, total)
    total
  end

  def record(user, amount:, reason:, reason_key:, metadata:)
    ApplicationRecord.transaction do
      user.coin_transactions.create!(amount: amount, reason: reason, reason_key: reason_key, metadata: metadata)
      # Atomic in SQL so concurrent grants can't lose an increment, and it keeps
      # the in-memory balance in step without marking the record dirty.
      user.increment!(:coins, amount.to_i)
    end
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false # already applied
  end

  private_class_method :record
end
