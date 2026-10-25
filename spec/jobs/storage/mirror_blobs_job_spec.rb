# frozen_string_literal: true

require "rails_helper"
require "active_job/continuation/test_helper"

RSpec.describe Storage::MirrorBlobsJob do
  include ActiveJob::TestHelper
  include ActiveJob::Continuation::TestHelper

  let(:primary) { ActiveStorage::Blob.services.fetch(:test) }
  let(:copy_root) { Dir.mktmpdir("mirror") }
  let(:copy) { ActiveStorage::Service::DiskService.new(root: copy_root).tap { it.name = :copy } }
  let(:mirror) { ActiveStorage::Service::MirrorService.new(primary: primary, mirrors: [ copy ]).tap { it.name = :mirror } }
  let!(:blobs) do
    Array.new(3) { |i| ActiveStorage::Blob.create_and_upload!(io: StringIO.new("file #{i}"), filename: "#{i}.png", service_name: "test") }
  end

  after { FileUtils.rm_rf(copy_root) }

  it "copies every blob to the mirrors" do
    allow(ActiveStorage::Blob).to receive(:service).and_return(mirror)

    described_class.perform_now

    expect(blobs.map { copy.exist?(it.key) }).to all(be(true))
    expect(copy.download(blobs.first.key)).to eq("file 0")
  end

  it "picks up after an interruption from the last blob it copied" do
    allow(ActiveStorage::Blob).to receive(:service).and_return(mirror)
    allow(mirror).to receive(:mirror).and_call_original

    described_class.perform_later
    # The cursor right after the first blob is copied.
    interrupt_job_during_step(described_class, :mirror, cursor: blobs.first.id.succ) { perform_enqueued_jobs }
    expect(copy.exist?(blobs.first.key)).to be(true)
    expect(copy.exist?(blobs.last.key)).to be(false)

    perform_enqueued_jobs

    expect(blobs.map { copy.exist?(it.key) }).to all(be(true))
    expect(mirror).to have_received(:mirror).exactly(3).times
  end

  it "does nothing when the service is not a mirror" do
    allow(Rails.logger).to receive(:info).and_call_original

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with(/not a mirror/)
    expect(Dir.children(copy_root)).to be_empty
  end
end
