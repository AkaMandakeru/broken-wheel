# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpoPushClient do
  let(:http) { instance_double(Net::HTTP) }

  def respond_with(klass, code, body)
    response = klass.new("1.1", code, "")
    allow(response).to receive(:body).and_return(body)
    allow(Net::HTTP).to receive(:start).with("exp.host", 443, hash_including(use_ssl: true)).and_yield(http)
    allow(http).to receive(:request).and_return(response)
  end

  it "posts the messages and returns the tickets" do
    respond_with(Net::HTTPOK, "200", { data: [ { status: "ok", id: "r-1" } ] }.to_json)

    tickets = described_class.new.send_messages([ { to: "ExponentPushToken[x]", title: "Hi" } ])

    expect(tickets).to eq([ { "status" => "ok", "id" => "r-1" } ])
    expect(http).to have_received(:request) do |request|
      expect(request.path).to eq("/--/api/v2/push/send")
      expect(JSON.parse(request.body)).to eq([ { "to" => "ExponentPushToken[x]", "title" => "Hi" } ])
      expect(request["Authorization"]).to be_nil
    end
  end

  it "sends the access token when one is set" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("EXPO_ACCESS_TOKEN").and_return("secret")
    respond_with(Net::HTTPOK, "200", { data: {} }.to_json)

    described_class.new.receipts([ "r-1" ])

    expect(http).to have_received(:request) do |request|
      expect(request.path).to eq("/--/api/v2/push/getReceipts")
      expect(request["Authorization"]).to eq("Bearer secret")
    end
  end

  it "reports rate limits and server errors as worth retrying" do
    respond_with(Net::HTTPTooManyRequests, "429", "")
    expect { described_class.new.send_messages([]) }.to raise_error(ExpoPushClient::Unavailable)

    respond_with(Net::HTTPBadGateway, "502", "")
    expect { described_class.new.send_messages([]) }.to raise_error(ExpoPushClient::Unavailable)
  end

  it "reports a network failure as worth retrying" do
    allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

    expect { described_class.new.send_messages([]) }.to raise_error(ExpoPushClient::Unavailable)
  end

  it "reports a rejected request as final" do
    respond_with(Net::HTTPBadRequest, "400", { errors: [ { code: "VALIDATION_ERROR" } ] }.to_json)

    expect { described_class.new.send_messages([]) }.to raise_error(ExpoPushClient::Error, /VALIDATION_ERROR/)
  end
end
