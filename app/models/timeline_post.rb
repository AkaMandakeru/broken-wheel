class TimelinePost < ApplicationRecord
  has_many_attached :images
  belongs_to :user
  belongs_to :challenge
  belongs_to :workout, optional: true
  has_many :timeline_post_comments, dependent: :destroy
end
