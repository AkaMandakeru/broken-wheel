# frozen_string_literal: true

# The body of a successful login, sign-up or refresh: an ApiSession::Tokens.
class SessionResource < ApplicationResource
  attribute(:token_type) { "Bearer" }
  attributes :access_token, :refresh_token

  attribute :access_token_expires_at do |tokens|
    tokens.session.access_token_expires_at.iso8601
  end

  attribute :refresh_token_expires_at do |tokens|
    tokens.session.expires_at.iso8601
  end

  attribute :user do |tokens|
    UserSummaryResource.new(tokens.session.user).serializable_hash
  end
end
