# frozen_string_literal: true

require "rails_helper"

RSpec.describe EngagementMailer do
  let(:season) { build_season(starts_at: Date.new(2026, 10, 1), ends_at: Date.new(2026, 10, 31)) }
  let(:user) { build_user(first_name: "Ana") }
  let(:event_date) { Date.new(2026, 10, 12) }
  let(:season_challenge) do
    challenge = build_challenge(key: "childrens_day_run", requirements: [ { metric: "distance_km", target: 5 } ],
                                starts_at: event_date, ends_at: event_date)
    season.season_challenges.create!(challenge: challenge, category: "special", xp_reward: 1000,
                                     coin_reward: 200, starts_at: event_date, ends_at: event_date)
  end

  let(:mail) { described_class.with(user: user, season_challenge: season_challenge).special_event_reminder }

  around do |example|
    travel_to(Time.find_zone("America/Sao_Paulo").local(2026, 10, 9, 12)) { example.run }
  end

  def attach_banner(record, file: "season_cover.png")
    record.attach(io: Rails.root.join("spec/fixtures/files/#{file}").open, filename: file, content_type: "image/png")
  end

  it "is addressed to the player and counts down to the event" do
    expect(mail.to).to eq([ user.email ])
    expect(mail.subject).to include(season_challenge.challenge.display_title)
    expect(mail.html_part.body.decoded).to include("is in 3 days")
    expect(mail.html_part.body.decoded).to include("+1000 XP")
    expect(mail.text_part.body.decoded).to include("/seasons/#{season.id}")
  end

  it "embeds the event's banner inline" do
    attach_banner(season_challenge.email_banner)

    banner = mail.attachments["banner.png"]
    expect(banner).to be_present
    expect(banner).to be_inline
    expect(mail.html_part.body.decoded).to include("cid:#{banner.cid}")
  end

  it "falls back to the season image when the event has no banner" do
    attach_banner(season.image)

    expect(mail.attachments["banner.png"]).to be_present
  end

  it "goes out without a picture when there is none" do
    expect(mail.attachments).to be_empty
    expect(mail.html_part.body.decoded).not_to include("<img")
  end

  it "carries a one-click unsubscribe" do
    expect(mail["List-Unsubscribe"].value).to match(%r{<http://example.com/email/unsubscribe/.+>})
    expect(mail["List-Unsubscribe-Post"].value).to eq("List-Unsubscribe=One-Click")
  end

  it "is written in the language the player last used" do
    user.remember_locale(:pt)

    expect(mail.subject).to include("está chegando")
    expect(mail.html_part.body.decoded).to include("Faltam 3 dias")
    expect(mail.html_part.body.decoded).to include("12 de outubro de 2026")
  end
end
