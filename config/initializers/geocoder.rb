Geocoder.configure(
  ip_lookup: :ipapi_com,
  use_https: false,
  timeout: 2,
  always_raise: [
    SocketError,
    Errno::ECONNREFUSED,
    Errno::EHOSTUNREACH,
    Net::ReadTimeout,
    Net::OpenTimeout,
    Geocoder::OverQueryLimitError,
    Geocoder::NetworkError
  ]
)
