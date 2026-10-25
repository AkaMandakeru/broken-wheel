# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounts::Deletion do
  let(:user) { build_user }
  let(:friend) { build_user(first_name: "Friend") }
  let(:season) { build_season }
  let(:challenge) { build_challenge(key: "run_10k", requirements: [ { metric: "distance_km", target: 10 } ]) }

  # Every foreign key that points at users, as [table, column]. Read from the
  # database so a table added later is covered without touching this spec.
  def user_foreign_keys
    connection = ActiveRecord::Base.connection
    connection.tables.flat_map do |table|
      connection.foreign_keys(table).select { |fk| fk.to_table == "users" }.map { |fk| [ table, fk.column ] }
    end
  end

  def rows_pointing_at(user_id)
    user_foreign_keys.to_h do |table, column|
      [ "#{table}.#{column}", ActiveRecord::Base.connection.select_value(
        "SELECT COUNT(*) FROM #{table} WHERE #{column} = #{user_id.to_i}"
      ).to_i ]
    end
  end

  # A player who has done a bit of everything, plus the rows other players
  # hold that point back at them.
  def give_user_a_history
    participation = challenge.challenge_participations.create!(user: user)
    workout = build_workout(user, date: Date.new(2026, 8, 3))
    workout.update!(challenge_participation: participation)
    challenge.challenge_participations.create!(user: friend, invited_by: user)

    founded = Club.create!(name: "Founded", sport: "run", created_by: user)
    Clubs::Membership.new(founded, user).join
    Clubs::Membership.new(founded, friend).join
    lonely = Club.create!(name: "Lonely", sport: "run", created_by: user)
    Clubs::Membership.new(lonely, user).join
    joined = Club.create!(name: "Joined", sport: "run", created_by: friend)
    Clubs::Membership.new(joined, friend).join
    Clubs::Membership.new(joined, user).join

    event = Event.create!(title: "City 10k", sport: "run")
    EventParticipation.create!(user: user, event: event, workout: workout)
    EventParticipation.create!(user: friend, event: event)

    own_post = TimelinePost.create!(user: user, challenge: challenge, workout: workout, content: "Done!")
    TimelinePostComment.create!(timeline_post: own_post, user: friend, content: "Nice")
    friends_post = TimelinePost.create!(user: friend, challenge: challenge, content: "Me too")
    TimelinePostComment.create!(timeline_post: friends_post, user: user, content: "Go!")

    badge = Badge.create!(name: "Finisher", icon: "🏁", badge_type: "season")
    user.user_badges.create!(badge: badge, earned_at: Time.current)
    AnalyticsEvent.create!(user: user, event_name: "user_signed_up")

    ContentReport.file(reporter: user, reportable: friends_post, reason: "spam")
    ContentReport.file(reporter: friend, reportable: user, reason: "harassment")
    closed, = ContentReport.file(reporter: friend, reportable: own_post, reason: "spam")
    closed.resolve!(status: "dismissed", by: user)
    UserBlock.create!(blocker: user, blocked: friend)
    UserBlock.create!(blocker: friend, blocked: user)

    user.coin_transactions.create!(amount: 10, reason: "daily", reason_key: "daily:1")
    user.user_xp_boosts.create!(source_key: "boost", multiplier: 2, starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
    user.user_cosmetics.create!(cosmetic: build_cosmetic(key: "cold_start"), source: "season_reward")

    season_participation = SeasonProgressService.ensure_participation(user, season)
    season.season_activities.create!(user: user, kind: "level_up")
    template = DailyChallengeTemplate.create!(season: season, key: "one", metric: "activity_count", target: 1,
                                              xp_reward: 50, coin_reward: 25)
    user.daily_challenge_assignments.create!(season: season, daily_challenge_template: template,
                                             challenge_date: Date.current)

    ticket = user.support_tickets.create!(subject: "Help", category: "general", source: "general", status: "open")
    ticket.support_messages.create!(user: user, body: "Please")

    user.create_strava_token!(refresh_token: "refresh", access_token: "access")
    user.push_subscriptions.create!(endpoint: "https://push.example/#{user.id}", p256dh_key: "k", auth_key: "a")
    user.device_tokens.create!(token: "ExponentPushToken[#{user.id}]", platform: "expo")
    user.idempotency_keys.create!(key: "k1", request_digest: "d")
    ApiSession.start!(user)

    { founded: founded, lonely: lonely, joined: joined, event: event, friends_post: friends_post,
      season_participation: season_participation, closed_report: closed }
  end

  it "deletes a player with rows in every table that points at users, and leaves nothing pointing at them" do
    history = give_user_a_history

    # The fixture must actually exercise every foreign key, or this proves nothing.
    expect(rows_pointing_at(user.id).select { |_fk, count| count.zero? }.keys).to be_empty

    described_class.call(user)

    expect(User.exists?(user.id)).to be(false)
    expect(rows_pointing_at(user.id).values).to all(be_zero)
    expect(SeasonParticipation.exists?(history[:season_participation].id)).to be(false)
    expect(SeasonActivity.where(user_id: user.id)).to be_empty
    expect(AnalyticsEvent.where(user_id: user.id)).to be_empty
  end

  it "keeps what other players share sane" do
    history = give_user_a_history

    described_class.call(user)

    # Clubs: the founder's club passes on, an empty one goes, counts drop.
    expect(history[:founded].reload).to have_attributes(created_by_id: friend.id, member_count: 1)
    expect(history[:founded].club_memberships.find_by(user: friend).role).to eq("admin")
    expect(Club.exists?(history[:lonely].id)).to be(false)
    expect(history[:joined].reload.member_count).to eq(1)

    # Events keep their counter right.
    expect(history[:event].reload.event_participations_count).to eq(1)

    # Friends keep their own posts, minus the deleted player's comments.
    expect(history[:friends_post].reload.timeline_post_comments).to be_empty
    expect(friend.challenge_participations.first.invited_by_id).to be_nil

    # Closed moderation history stays, without naming the player.
    expect(history[:closed_report].reload).to have_attributes(resolved_by_id: nil, reported_user_id: nil)
    expect(ContentReport.where(reportable_type: "User", reportable_id: user.id, status: "open")).to be_empty
    expect(UserBlock.where(blocker: friend)).to be_empty
    expect(User.exists?(friend.id)).to be(true)
  end

  it "rolls everything back when a step fails" do
    give_user_a_history
    allow(user).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)

    expect { described_class.call(user) }.to raise_error(ActiveRecord::RecordNotDestroyed)

    expect(User.exists?(user.id)).to be(true)
    expect(user.workouts.count).to eq(1)
    expect(Club.where(created_by: user).count).to eq(2)
  end

  describe ".request" do
    include ActiveJob::TestHelper

    it "locks the account, signs it out and schedules the deletion" do
      tokens = ApiSession.start!(user)

      described_class.request(user)

      expect(user.reload).to be_access_locked
      expect(ApiSession.authenticate_access(tokens.access_token)).to be_nil
      expect(Accounts::DeletionJob).to have_been_enqueued.with(user.id)
    end
  end
end

RSpec.describe Accounts::DeletionJob do
  it "deletes the account" do
    user = build_user
    build_workout(user, date: Date.new(2026, 8, 3))

    described_class.perform_now(user.id)

    expect(User.exists?(user.id)).to be(false)
  end

  it "does nothing for an account that is already gone" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
