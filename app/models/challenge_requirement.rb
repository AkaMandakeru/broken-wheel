# frozen_string_literal: true

# One condition of a challenge. A challenge is complete when every one of its
# requirements is satisfied.
class ChallengeRequirement < ApplicationRecord
  belongs_to :challenge

  COMPARATORS = %w[gte lte].freeze

  validates :metric, presence: true, inclusion: { in: ->(_r) { ChallengeMetrics.keys } }
  validates :comparator, inclusion: { in: COMPARATORS }
  validates :target, numericality: { greater_than: 0 }

  before_validation :apply_metric_defaults

  scope :ordered, -> { order(:position, :id) }

  def satisfied_by?(value)
    if comparator == "lte"
      value.present? && value.to_f.positive? && value.to_f <= target.to_f
    else
      value.to_f >= target.to_f
    end
  end

  # 0–100. `lte` goals (a target time) only read as complete or not — a partial
  # bar would imply you were "half way to being fast enough", which is meaningless.
  def percent_of(value)
    return satisfied_by?(value) ? 100 : 0 if comparator == "lte"
    return 0 if target.to_f.zero?

    [ ((value.to_f / target.to_f) * 100).round, 100 ].min
  end

  def requires_start_time?
    ChallengeMetrics.requires_start_time?(metric)
  end

  def display_unit
    unit.presence || ChallengeMetrics.unit_for(metric)
  end

  # Falls back to a generated sentence when a blueprint supplies no label key.
  def label
    return I18n.t(label_key, default: nil) if label_key.present?

    I18n.t(
      "challenges.requirements.#{metric}",
      count: target.to_f == target.to_i ? target.to_i : target.to_f,
      target: formatted_target,
      unit: I18n.t("enums.metric_units.#{display_unit}", default: display_unit),
      km: options["km"],
      hour: formatted_hour,
      default: "#{formatted_target} #{display_unit}"
    )
  end

  def formatted_target
    target.to_f == target.to_i ? target.to_i.to_s : format("%.2f", target).sub(/0+\z/, "").sub(/\.\z/, "")
  end

  private

  def formatted_hour
    return nil if options["hour"].blank?

    format("%02d:%02d", options["hour"].to_i, options["minute"].to_i)
  end

  def apply_metric_defaults
    return unless ChallengeMetrics.exists?(metric)

    self.comparator = ChallengeMetrics.comparator_for(metric).to_s if comparator.blank?
    self.unit = ChallengeMetrics.unit_for(metric) if unit.blank?
  end
end
