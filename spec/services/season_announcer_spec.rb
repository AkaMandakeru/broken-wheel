# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeasonAnnouncer do
  let(:season) { build_season(status: "upcoming", name: "Spring Push") }

  def pushes
    @pushes ||= []
  end

  before do
    allow(PushNotifier).to receive(:broadcast) { |**kw| pushes << kw }
    allow(SlackNotifier).to receive(:notify)
  end

  describe "announcing an open season" do
    before { season.update_columns(status: "active") }

    it "pushes to everyone who has notifications on" do
      described_class.call(season)

      expect(pushes.size).to eq(1)
      expect(pushes.first[:body]).to include("Spring Push")
      expect(pushes.first[:path]).to eq("/seasons/#{season.id}")
    end

    it "tells the team" do
      described_class.call(season)

      expect(SlackNotifier).to have_received(:notify)
        .with(:season_started, hash_including(subject: "Spring Push"))
    end

    it "records it on the season's activity feed" do
      described_class.call(season)

      expect(season.season_activities.where(kind: "season_started").count).to eq(1)
    end

    it "stamps when it was announced" do
      described_class.call(season)

      expect(season.reload.announced_at).to be_within(1.minute).of(Time.current)
    end
  end

  describe "not announcing twice" do
    before { season.update_columns(status: "active") }

    # Flipping status back and forth, a retried job, or a re-import must not
    # notify everyone again.
    it "is a no-op once already announced" do
      described_class.call(season)

      expect(described_class.call(season)).to be(false)
      expect(pushes.size).to eq(1)
    end

    it "sends again only when explicitly forced" do
      described_class.call(season)

      expect(described_class.call(season, force: true)).to be(true)
      expect(pushes.size).to eq(2)
    end
  end

  describe "when it stays quiet" do
    it "does nothing for a season that hasn't opened" do
      expect(described_class.call(season)).to be(false)
      expect(pushes).to be_empty
    end

    it "does nothing for one that has ended" do
      season.update_columns(status: "ended")

      expect(described_class.call(season)).to be(false)
    end
  end

  describe "the trigger" do
    it "fires when a season is activated" do
      upcoming = build_season(status: "upcoming")

      expect { upcoming.update!(status: "active") }
        .to have_enqueued_job(AnnounceSeasonJob).with(upcoming.id)
    end

    it "fires for a season created already active" do
      expect { build_season(status: "active") }.to have_enqueued_job(AnnounceSeasonJob)
    end

    # A season that was live before announcements existed was backfilled as
    # already announced; editing it must not notify anyone.
    it "stays quiet when an already-announced season is edited" do
      live = build_season(status: "active")
      live.update_columns(announced_at: 2.days.ago)

      expect { live.update!(name: "Renamed") }.not_to have_enqueued_job(AnnounceSeasonJob)
    end

    it "stays quiet on any change that isn't the status opening" do
      upcoming = build_season(status: "upcoming")

      expect { upcoming.update!(name: "Still Upcoming") }.not_to have_enqueued_job(AnnounceSeasonJob)
    end
  end
end

RSpec.describe Seasons::Announcement do
  let(:user) { build_user }

  it "shows a recently announced active season" do
    season = build_season(status: "active", name: "Now Running")
    season.update_columns(announced_at: 1.hour.ago)

    expect(described_class.for(user)&.name).to eq("Now Running")
  end

  it "shows nothing to a signed-out visitor" do
    build_season(status: "active").update_columns(announced_at: 1.hour.ago)

    expect(described_class.for(nil)).to be_nil
  end

  it "stops showing once dismissed" do
    season = build_season(status: "active")
    season.update_columns(announced_at: 1.hour.ago)
    user.dismiss_season_announcement(season.id)

    expect(described_class.for(user)).to be_nil
  end

  # After a week it isn't news, and the season page speaks for itself.
  it "stops showing after the visible window" do
    season = build_season(status: "active")
    season.update_columns(announced_at: 8.days.ago)

    expect(described_class.for(user)).to be_nil
  end

  it "ignores a season that was never announced" do
    build_season(status: "active").update_columns(announced_at: nil)

    expect(described_class.for(user)).to be_nil
  end

  it "keeps dismissals separate between users" do
    season = build_season(status: "active")
    season.update_columns(announced_at: 1.hour.ago)
    user.dismiss_season_announcement(season.id)

    expect(described_class.for(build_user)).to be_present
  end
end
