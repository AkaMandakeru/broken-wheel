# frozen_string_literal: true

module SupportHelper
  def status_badge_class(status)
    case status
    when "open"     then "bg-amber-100 text-amber-700"
    when "answered" then "bg-green-100 text-green-700"
    when "closed"   then "bg-gray-100 text-gray-600"
    else "bg-gray-100 text-gray-600"
    end
  end
end
