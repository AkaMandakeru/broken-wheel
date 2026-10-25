# frozen_string_literal: true

# A player flagging a post, comment, club or person for the team to review
# (App Store guideline 1.2).
class ContentReport < ApplicationRecord
  REASONS = %w[spam harassment hate sexual violence other].freeze
  STATUSES = %w[open dismissed actioned].freeze

  # The names the app sends, and the models they stand for.
  REPORTABLE_TYPES = {
    "timeline_post" => "TimelinePost",
    "timeline_post_comment" => "TimelinePostComment",
    "club" => "Club",
    "user" => "User"
  }.freeze

  # Content the team can take down from the review screen.
  REMOVABLE_TYPES = %w[TimelinePost TimelinePostComment].freeze

  belongs_to :reporter, class_name: "User"
  # Optional so a report outlives the post it was about once that is removed.
  belongs_to :reportable, polymorphic: true, optional: true
  belongs_to :reported_user, class_name: "User", optional: true
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :reportable, presence: true, on: :create
  validates :reportable_type, inclusion: { in: REPORTABLE_TYPES.values }
  validates :reason, inclusion: { in: REASONS }
  validates :status, inclusion: { in: STATUSES }
  validates :details, length: { maximum: 2000 }
  validate :not_about_self, on: :create

  before_validation :set_reported_user, on: :create
  after_create_commit :notify_team

  scope :open, -> { where(status: "open") }
  scope :with_status, ->(status) { status.present? ? where(status: status) : all }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  # The model behind an API name ("timeline_post"), or nil for anything else.
  def self.reportable_class(name)
    REPORTABLE_TYPES[name.to_s]&.constantize
  end

  # One report per player per item: reporting again hands back the first one.
  # Returns [report, created?].
  def self.file(reporter:, reportable:, reason:, details: nil)
    existing = find_by(reporter: reporter, reportable: reportable)
    return [ existing, false ] if existing

    report = new(reporter: reporter, reportable: reportable, reason: reason, details: details)
    [ report, report.save ]
  rescue ActiveRecord::RecordNotUnique
    [ find_by!(reporter: reporter, reportable: reportable), false ]
  end

  def open? = status == "open"

  def resolve!(status:, by:)
    if status == "open"
      update!(status: status, resolved_by: nil, resolved_at: nil)
    else
      update!(status: status, resolved_by: by, resolved_at: Time.current)
    end
  end

  def removable? = reportable.present? && REMOVABLE_TYPES.include?(reportable_type)

  # Takes the reported post or comment down and closes every open report about
  # it, so the queue doesn't keep showing content that is already gone.
  def remove_content!(by:)
    return false unless removable?

    transaction do
      siblings = self.class.open.where(reportable_type: reportable_type, reportable_id: reportable_id).where.not(id: id)
      siblings.find_each { |report| report.resolve!(status: "actioned", by: by) }
      reportable.destroy!
      resolve!(status: "actioned", by: by)
    end
    true
  end

  # What the reported thing says, for the review screen.
  def reportable_excerpt
    case reportable
    when TimelinePost, TimelinePostComment then reportable.content
    when Club then [ reportable.name, reportable.description ].compact_blank.join(" — ")
    when User then [ reportable.first_name, reportable.last_name ].compact_blank.join(" ")
    end
  end

  def api_reportable_type = REPORTABLE_TYPES.key(reportable_type)

  private

  def set_reported_user
    self.reported_user ||= case reportable
    when TimelinePost, TimelinePostComment then reportable.user
    when Club then reportable.created_by
    when User then reportable
    end
  end

  def not_about_self
    errors.add(:reportable, :invalid) if reported_user_id.present? && reported_user_id == reporter_id
  end

  def notify_team
    SlackNotifier.notify(
      :content_reported,
      user: reporter,
      extra: {
        "Report" => "##{id}",
        "Content" => "#{api_reportable_type} ##{reportable_id}",
        "Reason" => reason,
        "Reported user" => reported_user && "#{reported_user.first_name} #{reported_user.last_name} (##{reported_user.id})",
        "Details" => details.presence&.truncate(200)
      }
    )
  end
end
