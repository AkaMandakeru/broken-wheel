class User < ApplicationRecord
  has_one_attached :avatar
  has_one :strava_token, dependent: :destroy

  has_many :challenge_participations
  has_many :event_participations
  has_many :events, through: :event_participations
  has_many :workouts
  has_many :user_badges
  has_many :badges, through: :user_badges
  has_many :club_memberships
  has_many :clubs, through: :club_memberships
  has_many :support_tickets, dependent: :destroy
  has_many :support_messages, dependent: :destroy

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :lockable, :timeoutable

  validates :first_name, :last_name, presence: true

  def connected_to_strava?
    strava_token.present? && strava_token.refresh_token.present?
  end
end
