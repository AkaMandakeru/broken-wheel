# frozen_string_literal: true

# A message in a support conversation. The team's replies carry no user: the
# player sees "the team", never an admin's name or email.
class SupportMessageResource < ApplicationResource
  attributes :id, :body, :from_admin

  attribute(:created_at) { |message| message.created_at.iso8601 }
end
