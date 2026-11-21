# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "review:account" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "review:account" } }

  let(:task) { Rake::Task["review:account"] }

  before { allow(SlackNotifier).to receive(:notify) }
  after { task.reenable }

  def run(email = nil, password: "reviewpass123")
    ENV["REVIEW_PASSWORD"] = password
    expect { task.invoke(*email) }.to output.to_stdout
  ensure
    ENV.delete("REVIEW_PASSWORD")
  end

  it "creates an account that signs in, without announcing a signup" do
    run("reviewer@example.com")

    user = User.find_by!(email: "reviewer@example.com")
    expect(user.valid_password?("reviewpass123")).to be(true)
    expect(SlackNotifier).not_to have_received(:notify)
  end

  it "resets the password and unlocks the account when run again" do
    run("reviewer@example.com")
    User.find_by!(email: "reviewer@example.com").lock_access!(send_instructions: false)

    task.reenable
    run("reviewer@example.com", password: "newpass12345")

    user = User.find_by!(email: "reviewer@example.com")
    expect(user.valid_password?("newpass12345")).to be(true)
    expect(user.access_locked?).to be(false)
    expect(User.where(email: "reviewer@example.com").count).to eq(1)
  end
end
