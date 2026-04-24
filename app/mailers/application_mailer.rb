class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "Forum <noreply@example.com>")
  layout "mailer"
end
