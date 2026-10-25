class TimelinePostComment < ApplicationRecord
  MAX_CONTENT_LENGTH = 1000

  belongs_to :timeline_post
  belongs_to :user

  validates :content, presence: true, length: { maximum: MAX_CONTENT_LENGTH }

  scope :visible_to, ->(viewer) { viewer ? where.not(user_id: UserBlock.blocked_ids_by(viewer)) : all }
end
