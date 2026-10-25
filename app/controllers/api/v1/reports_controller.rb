# frozen_string_literal: true

module Api
  module V1
    # Reporting a post, comment, club or player (App Store guideline 1.2).
    # Reporting the same thing twice is not an error: the first report comes
    # back with 200, so a retry or a second tap needs no special handling.
    class ReportsController < BaseController
      rate_limit to: 30, within: 1.hour, only: :create, by: -> { current_user.id },
                 with: -> { render_error :too_many_requests, "rate_limited" }

      def create
        type, id, reason = params.expect(:reportable_type, :reportable_id, :reason)
        klass = ContentReport.reportable_class(type)
        return render_error(:unprocessable_content, "validation_failed", fields: { reportable_type: [ I18n.t("api.reports.unknown_type") ] }) unless klass

        reportable = klass.find(id)
        report, created = ContentReport.file(reporter: current_user, reportable: reportable,
                                             reason: reason, details: params[:details].presence)
        return render_report_invalid(report) unless report.persisted?

        track_event "api.content_report.created", report_id: report.id, reportable_type: type if created
        render_resource ContentReportResource, report, status: created ? :created : :ok
      end

      private

      def render_report_invalid(report)
        return render_error(:unprocessable_content, "cannot_report_self") if report.reported_user_id == current_user.id

        render_invalid report
      end
    end
  end
end
