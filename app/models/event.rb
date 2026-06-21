class Event < ApplicationRecord
  has_one_attached :image

  has_many :event_participations, dependent: :destroy
  has_many :participants, through: :event_participations, source: :user

  SPORTS = %w[run bike soccer].freeze
  STATUSES = %w[upcoming completed].freeze
  # Common race distances offered as quick-pick checkboxes in the admin form.
  STANDARD_DISTANCES = [ 5, 10, 21, 42 ].freeze

  validates :title, presence: true
  validates :sport, inclusion: { in: SPORTS }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }, allow_blank: true
  validates :distance_km, numericality: { greater_than: 0 }, allow_nil: true

  scope :upcoming, -> { where(status: "upcoming") }
  scope :by_date, -> { order(event_date: :asc) }

  after_create_commit :push_new_event_notification

  # Accepts checkbox values and/or a comma/space separated string, and stores a
  # clean, de-duplicated, sorted list of distances (in km) as numbers.
  def distances=(value)
    list = Array(value)
             .flat_map { |v| v.to_s.split(/[,;\s]+/) }
             .map { |s| s.strip.to_f }
             .reject(&:zero?)
    super(list.uniq.sort)
  end

  def distances?
    distances.present?
  end

  def upcoming?
    status == "upcoming"
  end

  # => { 5.0 => 3, 10.0 => 7, ... } including only chosen distances.
  # Keys are floats so they line up with the values stored in #distances.
  def participation_counts_by_distance
    event_participations.where.not(selected_distance_km: nil)
                        .group(:selected_distance_km).count
                        .transform_keys(&:to_f)
  end

  private

  def push_new_event_notification
    PushNotifier.broadcast(
      title: I18n.t("push.event.title"),
      body: I18n.t("push.event.body", title: title),
      path: Rails.application.routes.url_helpers.event_path(self),
      tag: "event-#{id}"
    )
  end
end
