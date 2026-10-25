# frozen_string_literal: true

# What the reporter gets back: enough to show "thanks, we'll take a look",
# never who else reported the same thing.
class ContentReportResource < ApplicationResource
  attributes :id, :reportable_id, :reason, :details, :status

  attribute(:reportable_type, &:api_reportable_type)
  attribute(:created_at) { |report| report.created_at.iso8601 }
end
