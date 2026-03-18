class ChallengeParticipation < ApplicationRecord
  belongs_to :challenge
  belongs_to :user
  belongs_to :invited_by, class_name: "User", optional: true
  has_many :workouts

  before_validation :generate_invite_code, on: :create

  private

  def generate_invite_code
    self.invite_code ||= SecureRandom.hex(8)
  end
end
