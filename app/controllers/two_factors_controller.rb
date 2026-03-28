class TwoFactorsController < ApplicationController
  before_action :require_login, except: [:verify, :confirm_verify]

  def setup
    @secret = session[:pending_totp_secret] ||= ROTP::Base32.random
    @qr_svg = build_qr_svg(@secret)
  end

  def confirm_setup
    secret = session[:pending_totp_secret]
    redirect_to setup_two_factor_path and return unless secret

    totp = ROTP::TOTP.new(secret)
    if totp.verify(params[:code].to_s.strip, drift_behind: 30, drift_ahead: 30)
      current_user.update!(totp_secret: secret)
      session.delete(:pending_totp_secret)
      @backup_codes = BackupCode.generate_for(current_user)
      render :backup_codes
    else
      @secret = secret
      @qr_svg = build_qr_svg(@secret)
      flash.now[:alert] = "Invalid code. Please try again."
      render :setup, status: :unprocessable_entity
    end
  end

  def verify
    redirect_to root_path and return unless session[:awaiting_2fa]
  end

  def confirm_verify
    redirect_to root_path and return unless session[:awaiting_2fa]

    throttle = LoginThrottle.new(request.remote_ip)
    if throttle.throttled?
      flash.now[:alert] = "Too many failed attempts. Please wait before trying again."
      render :verify, status: :too_many_requests
      return
    end

    user = User.find_by(id: session[:awaiting_2fa])
    unless user
      reset_session
      redirect_to login_path, alert: "Session expired. Please log in again."
      return
    end

    submitted = params[:code].to_s.strip.gsub(/\s/, "")
    totp = ROTP::TOTP.new(user.totp_secret)
    valid = totp.verify(submitted, drift_behind: 30, drift_ahead: 30) ||
            BackupCode.consume_for(user, submitted)

    if valid
      throttle.clear!
      reset_session
      session[:user_id] = user.id
      redirect_to root_path, notice: "Welcome back, #{user.name}!"
    else
      throttle.record_failure!
      flash.now[:alert] = "Invalid code."
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user.authenticate(params[:current_password].to_s)
      redirect_to edit_user_path(current_user), alert: "Incorrect password."
      return
    end

    current_user.update!(totp_secret: nil)
    current_user.backup_codes.destroy_all
    redirect_to edit_user_path(current_user), notice: "Two-factor authentication disabled."
  end

  def regenerate_backup_codes
    unless current_user.authenticate(params[:current_password].to_s)
      redirect_to edit_user_path(current_user), alert: "Incorrect password."
      return
    end

    current_user.backup_codes.destroy_all
    @backup_codes = BackupCode.generate_for(current_user)
    render :backup_codes
  end

  private

  def build_qr_svg(secret)
    totp = ROTP::TOTP.new(secret, issuer: "Forum")
    uri  = totp.provisioning_uri(current_user.email)
    RQRCode::QRCode.new(uri).as_svg(module_size: 4)
  end
end
