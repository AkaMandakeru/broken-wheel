# frozen_string_literal: true

module Accounts
  # Deletes an account the player asked to close from the app. Takes an id, not
  # the record, so a retry after the account is already gone is a no-op rather
  # than a deserialization error.
  class DeletionJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer

    def perform(user_id)
      user = User.find_by(id: user_id)
      return if user.nil?

      Accounts::Deletion.call(user)
    end
  end
end
