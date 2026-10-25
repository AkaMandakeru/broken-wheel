# frozen_string_literal: true

# A thin client for Expo's push API (https://docs.expo.dev/push-notifications/sending-notifications/).
# Sending returns one ticket per message, in order; a ticket's id is later
# exchanged for a receipt, which is where most delivery errors show up.
class ExpoPushClient
  BASE_URL = "https://exp.host/--/api/v2/push"
  TIMEOUT = 10
  # Expo's per-request limits.
  MAX_MESSAGES = 100
  MAX_RECEIPT_IDS = 1000

  # Rate limited, Expo is down or the network failed: worth trying again.
  class Unavailable < StandardError; end
  # Expo rejected the request itself (bad payload, bad access token).
  class Error < StandardError; end

  # Tickets: [{ "status" => "ok", "id" => "…" } | { "status" => "error", "details" => { "error" => "DeviceNotRegistered" } }]
  def send_messages(messages)
    post("send", messages).fetch("data")
  end

  # { receipt_id => { "status" => "ok" | "error", "details" => { "error" => … } } }
  def receipts(ids)
    post("getReceipts", { ids: ids }).fetch("data")
  end

  private

  def post(action, body)
    uri = URI.parse("#{BASE_URL}/#{action}")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    # Only needed when "enhanced push security" is on for the Expo project.
    request["Authorization"] = "Bearer #{access_token}" if access_token.present?
    request.body = body.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(request)
    end

    case response
    when Net::HTTPSuccess then JSON.parse(response.body)
    when Net::HTTPTooManyRequests, Net::HTTPServerError then raise Unavailable, "Expo #{action}: #{response.code}"
    else raise Error, "Expo #{action}: #{response.code} #{response.body.to_s.truncate(300)}"
    end
  rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
    raise Unavailable, "Expo #{action}: #{e.class}: #{e.message}"
  end

  def access_token = ENV["EXPO_ACCESS_TOKEN"]
end
