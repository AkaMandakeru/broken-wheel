# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin content reports", type: :request do
  let(:admin) { build_user(admin: true) }
  let(:reporter) { build_user(first_name: "Ana") }
  let(:author) { build_user(first_name: "Troll") }
  let(:challenge) { build_challenge(key: "admin_reports", requirements: [ { metric: "distance_km", target: 1 } ]) }
  let(:timeline_post) { challenge.timeline_posts.create!(user: author, content: "Buy followers now") }
  let!(:report) { ContentReport.file(reporter: reporter, reportable: timeline_post, reason: "spam", details: "Obvious spam").first }

  before { sign_in admin }

  it "lists reports, filtered by status" do
    dismissed = ContentReport.file(reporter: reporter, reportable: author, reason: "harassment").first
    dismissed.resolve!(status: "dismissed", by: admin)

    get admin_content_reports_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Buy followers now", "Troll Runner")

    get admin_content_reports_path(status: "open")
    expect(response.body).to include("Buy followers now")
    expect(response.body).not_to include(admin_content_report_path(dismissed))
  end

  it "shows a report with the content and who is responsible" do
    get admin_content_report_path(report)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Buy followers now", "Obvious spam", author.email)
  end

  it "dismisses a report, recording who resolved it" do
    patch admin_content_report_path(report), params: { content_report: { status: "dismissed" } }

    expect(response).to redirect_to(admin_content_report_path(report))
    expect(report.reload).to have_attributes(status: "dismissed", resolved_by: admin)
    expect(report.resolved_at).to be_present
  end

  it "reopens a resolved report" do
    report.resolve!(status: "actioned", by: admin)

    patch admin_content_report_path(report), params: { content_report: { status: "open" } }

    expect(report.reload).to have_attributes(status: "open", resolved_by: nil, resolved_at: nil)
  end

  it "takes the content down and closes every report about it" do
    other_report = ContentReport.file(reporter: build_user, reportable: timeline_post, reason: "hate").first

    patch admin_content_report_path(report), params: { remove_content: "1" }

    expect(TimelinePost.exists?(timeline_post.id)).to be(false)
    expect([ report.reload.status, other_report.reload.status ]).to eq(%w[actioned actioned])

    get admin_content_report_path(report)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin.content_reports.removed_content"))
  end

  it "shows the queue in the admin navigation" do
    get admin_root_path

    expect(response.body).to include(admin_content_reports_path)
  end

  it "keeps players out" do
    sign_in reporter

    get admin_content_reports_path

    expect(response).to redirect_to(root_path)
  end
end
