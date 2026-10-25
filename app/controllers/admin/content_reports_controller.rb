# frozen_string_literal: true

module Admin
  # The moderation queue for reports filed from the app (App Store guideline
  # 1.2): review, then dismiss, mark as actioned or take the content down.
  class ContentReportsController < BaseController
    before_action :set_report, only: [ :show, :update ]

    def index
      @status = params[:status].presence_in(ContentReport::STATUSES)
      @reports = ContentReport.with_status(@status).includes(:reporter, :reported_user, :reportable).recent_first.limit(200)
      @open_count = ContentReport.open.count
    end

    def show
      @related_reports = ContentReport.where(reportable_type: @report.reportable_type, reportable_id: @report.reportable_id)
                                      .where.not(id: @report.id).includes(:reporter).recent_first
    end

    def update
      if params[:remove_content].present?
        notice = @report.remove_content!(by: current_user) ? "removed" : "not_removable"
      else
        status = params.dig(:content_report, :status).presence_in(ContentReport::STATUSES)
        @report.resolve!(status: status, by: current_user) if status
        notice = "updated"
      end

      redirect_to admin_content_report_path(@report), notice: t("admin.flashes.content_reports.#{notice}")
    end

    private

    def set_report
      @report = ContentReport.find(params[:id])
    end
  end
end
