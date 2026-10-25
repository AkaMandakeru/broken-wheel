class Club < ApplicationRecord
  SPORTS = %w[run bike soccer].freeze

  belongs_to :created_by, class_name: "User"
  has_many :club_memberships
  has_many :members, through: :club_memberships, source: :user

  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 2000 }
  validates :sport, inclusion: { in: SPORTS }, allow_blank: true

  # The clubs list: biggest first, narrowed to the player's sports when they
  # picked any.
  def self.for_sports(sports)
    sports = Array(sports).compact_blank
    scope = includes(:created_by).order(member_count: :desc)
    sports.any? ? scope.where(sport: sports) : scope
  end
end
