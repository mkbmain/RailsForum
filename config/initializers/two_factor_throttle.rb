Rails.application.config.x.two_factor_max_attempts    = ENV.fetch("TWO_FACTOR_MAX_ATTEMPTS", 5).to_i
Rails.application.config.x.two_factor_lockout_minutes = ENV.fetch("TWO_FACTOR_LOCKOUT_MINUTES", 15).to_i
