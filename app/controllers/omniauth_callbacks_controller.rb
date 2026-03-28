class OmniauthCallbacksController < ApplicationController
  PROVIDER_IDS = {
    "google_oauth2"   => Provider::GOOGLE,
    "microsoft_graph" => Provider::MICROSOFT
  }.freeze

  def handle
    auth = request.env["omniauth.auth"]

    unless auth
      redirect_to login_path, alert: "Authentication error. Please try signing in again."
      return
    end

    provider_id = PROVIDER_IDS[auth.provider]

    unless provider_id
      redirect_to login_path, alert: "Unknown provider."
      return
    end

    user = User.from_omniauth(auth, provider_id)
    user.update_column(:email_verified_at, Time.current) if user.email_verified_at.nil?
    reset_session
    session[:user_id] = user.id
    redirect_to root_path, notice: "Signed in as #{user.name}."
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "OmniAuth user save failed: #{e.record.errors.full_messages.join(', ')}"
    redirect_to login_path, alert: "Sign-in failed. Please try again."
  end

  def failure
    redirect_to login_path, alert: "Authentication failed: #{params[:message].to_s.humanize}."
  end
end
