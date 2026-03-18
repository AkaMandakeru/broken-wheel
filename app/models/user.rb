class User < ApplicationRecord
  has_one_attached :avatar

  has_many :challenge_participations
  has_many :workouts
  has_many :user_badges
  has_many :badges, through: :user_badges
  has_many :club_memberships
  has_many :clubs, through: :club_memberships

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :timeoutable

  validates :first_name, :last_name, presence: true
end
