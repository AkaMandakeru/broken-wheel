class TimelinePost < ApplicationRecord
  # More would turn one post into a photo album; the app's picker stops here too.
  MAX_IMAGES = 6
  MAX_CONTENT_LENGTH = 2000

  has_many_attached :images do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 480, 480 ], preprocessed: true
    attachable.variant :large, resize_to_limit: [ 1600, 1600 ], preprocessed: true
  end
  belongs_to :user
  belongs_to :challenge
  belongs_to :workout, optional: true
  has_many :timeline_post_comments, dependent: :destroy

  validates :content, length: { maximum: MAX_CONTENT_LENGTH }
  validate :content_or_images
  validate :images_within_limit
  validate :workout_belongs_to_user

  # Hides the posts of everyone `viewer` has blocked (App Store guideline 1.2).
  scope :visible_to, ->(viewer) { viewer ? where.not(user_id: UserBlock.blocked_ids_by(viewer)) : all }

  private

  def content_or_images
    errors.add(:content, :blank) if content.blank? && !images.attached?
  end

  def images_within_limit
    errors.add(:images, :too_many, count: MAX_IMAGES) if images.size > MAX_IMAGES
  end

  # A post can only show off the author's own workout.
  def workout_belongs_to_user
    return if workout.nil? || workout.user_id == user_id

    errors.add(:workout, :invalid)
  end
end
