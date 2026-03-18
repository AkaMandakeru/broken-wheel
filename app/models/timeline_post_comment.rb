class TimelinePostComment < ApplicationRecord
  belongs_to :timeline_post
  belongs_to :user
end
