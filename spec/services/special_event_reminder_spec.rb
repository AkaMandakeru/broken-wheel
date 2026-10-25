# frozen_string_literal: true

require "rails_helper"

RSpec.describe SpecialEventReminder do
  include ActiveJob::TestHelper

  let(:season) { build_season(starts_at: Date.new(2026, 10, 1), ends_at: Date.new(2026, 10, 31)) }
  let(:childrens_day) { special_event("childrens_day", Date.new(2026, 10, 12)) }

  def special_event(key, date, category: "special")
    challenge = build_challenge(key: key, requirements: [ { metric: "distance_km", target: 5 } ],
                                starts_at: date, ends_at: date)
    season.season_challenges.create!(challenge: challenge, category: category, xp_reward: 1000,
                                     coin_reward: 200, starts_at: date, ends_at: date)
  end

  # Midday in São Paulo, so the season's calendar and UTC agree on the date.
  def on(date, &block)
    travel_to(Time.find_zone("America/Sao_Paulo").local(date.year, date.month, date.day, 12), &block)
  end

  describe ".due" do
    it "is due three days before the event" do
      childrens_day
      on(Date.new(2026, 10, 9)) { expect(described_class.due).to eq([ childrens_day ]) }
    end

    it "is not due four days before" do
      childrens_day
      on(Date.new(2026, 10, 8)) { expect(described_class.due).to be_empty }
    end

    # A scheduler run that was missed must not lose the event.
    it "is still due the day before when the earlier runs were missed" do
      childrens_day
      on(Date.new(2026, 10, 11)) { expect(described_class.due).to eq([ childrens_day ]) }
    end

    it "is no longer due on the day itself" do
      childrens_day
      on(Date.new(2026, 10, 12)) { expect(described_class.due).to be_empty }
    end

    it "is not due once already sent" do
      childrens_day.update_columns(reminder_sent_at: Time.current)
      on(Date.new(2026, 10, 9)) { expect(described_class.due).to be_empty }
    end

    it "ignores challenges that are not special" do
      special_event("week_3", Date.new(2026, 10, 12), category: "weekly")
      on(Date.new(2026, 10, 9)) { expect(described_class.due).to be_empty }
    end

    it "ignores seasons that are not active" do
      childrens_day
      season.update_columns(status: "upcoming")
      on(Date.new(2026, 10, 9)) { expect(described_class.due).to be_empty }
    end
  end

  describe ".call" do
    let!(:runner) { build_user }
    let!(:opted_out) { build_user.tap(&:unsubscribe_from_emails!) }
    let!(:bot) { build_user(email: "bot-x@#{SeasonSandbox::BOT_EMAIL_DOMAIN}") }

    it "emails everyone reachable — opted-out players and bots excluded" do
      expect { described_class.call(childrens_day) }
        .to have_enqueued_mail(EngagementMailer, :special_event_reminder)
        .with(params: { user: runner, season_challenge: childrens_day }, args: [])
        .exactly(:once)
    end

    it "stamps when it was sent" do
      described_class.call(childrens_day)

      expect(childrens_day.reload.reminder_sent_at).to be_within(1.minute).of(Time.current)
    end

    it "never sends twice" do
      described_class.call(childrens_day)

      expect(described_class.call(childrens_day)).to be(false)
      expect(enqueued_jobs.count { |job| job["job_class"] == "ActionMailer::MailDeliveryJob" }).to eq(1)
    end

    it "sends again when forced" do
      described_class.call(childrens_day)

      expect(described_class.call(childrens_day, force: true)).to eq(1)
    end

    it "refuses challenges that are not special" do
      weekly = special_event("week_3", Date.new(2026, 10, 12), category: "weekly")

      expect(described_class.call(weekly)).to be(false)
      expect(weekly.reload.reminder_sent_at).to be_nil
    end
  end

  describe SpecialEventRemindersJob do
    it "sends the reminders that are due" do
      childrens_day
      build_user

      on(Date.new(2026, 10, 9)) do
        expect { described_class.perform_now }
          .to have_enqueued_mail(EngagementMailer, :special_event_reminder)
      end
      expect(childrens_day.reload.reminder_sent_at).to be_present
    end
  end
end
