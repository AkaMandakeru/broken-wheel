class ApplicationMailer < ActionMailer::Base
  # The sending address has to belong to a domain verified with the email
  # provider (SPF/DKIM), so it comes from the environment rather than code.
  default from: ENV.fetch("MAILER_FROM", "Broken Wheels <no-reply@example.com>")
  layout "mailer"
end
