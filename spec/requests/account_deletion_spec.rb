# frozen_string_literal: true

require "rails_helper"

# Devise's "Cancel my account". Its own destroy is a bare user.destroy, which
# the foreign keys refuse as soon as the player has done anything.
RSpec.describe "Cancelling an account on the web", type: :request do
  let(:user) { build_user }

  before { sign_in user }

  it "deletes a player who has workouts, badges and a club" do
    build_workout(user, date: Date.new(2026, 8, 3))
    club = Club.create!(name: "Founded", sport: "run", created_by: user)
    Clubs::Membership.new(club, user).join
    user.user_badges.create!(badge: Badge.create!(name: "Finisher", badge_type: "season"), earned_at: Time.current)

    delete user_registration_path

    expect(response).to redirect_to(root_path)
    expect(User.exists?(user.id)).to be(false)
  end
end
