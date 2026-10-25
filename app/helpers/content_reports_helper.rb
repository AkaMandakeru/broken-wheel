# frozen_string_literal: true

module ContentReportsHelper
  def content_report_badge_class(status)
    case status
    when "open"      then "bg-amber-100 text-amber-700"
    when "actioned"  then "bg-red-100 text-red-700"
    else "bg-gray-100 text-gray-600"
    end
  end

  def content_report_user_name(user)
    return t("admin.content_reports.deleted_user") if user.nil?

    [ user.first_name, user.last_name ].compact_blank.join(" ").presence || user.email
  end
end
