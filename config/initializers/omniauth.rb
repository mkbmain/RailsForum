Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           ENV.fetch("GOOGLE_CLIENT_ID", ""),
           ENV.fetch("GOOGLE_CLIENT_SECRET", ""),
           scope: "email,profile"

  provider :microsoft_graph,
           ENV.fetch("MICROSOFT_CLIENT_ID", ""),
           ENV.fetch("MICROSOFT_CLIENT_SECRET", ""),
           scope: "openid email profile"
end

OmniAuth.config.on_failure = proc { |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
}
