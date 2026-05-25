# frozen_string_literal: true

class AnalyticsEvent < ApplicationRecord
  belongs_to :user, optional: true
end
