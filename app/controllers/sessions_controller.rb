class SessionsController < ApplicationController
  def new
    redirect_to(root_path) and return if logged_in?
  end

  def create
    throttle = LoginThrottle.new(request.remote_ip)

    if throttle.throttled?
      flash.now[:alert] = "Too many failed login attempts. Please wait before trying again."
      render :new, status: :too_many_requests
      return
    end

    user = User.find_by(email: params[:email].to_s.downcase)
    if user&.authenticate(params[:password])
      if user.totp_enabled?
        reset_session
        session[:awaiting_2fa] = user.id
        redirect_to verify_two_factor_path
      else
        throttle.clear!
        reset_session
        session[:user_id] = user.id
        redirect_to root_path, notice: "Welcome back, #{user.name}!"
      end
    else
      throttle.record_failure!
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Logged out."
  end
end
