# config/initializers/forum_settings.rb
EDIT_WINDOW_SECONDS     = ENV.fetch("EDIT_WINDOW_SECONDS", 3600).to_i
SESSION_TIMEOUT_MINUTES = ENV.fetch("SESSION_TIMEOUT_MINUTES", 2880).to_i
