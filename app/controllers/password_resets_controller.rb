class PasswordResetsController < ApplicationController
  def new
  end

  def create
    email = params[:email].to_s.downcase.strip
    user = User.find_by(email: email)

    if user&.internal?
      reset = user.password_reset

      if reset&.reusable?
        unless reset.on_cooldown?
          reset.update!(last_sent_at: Time.current)
          UserMailer.password_reset(reset).deliver_later
        end
      else
        reset&.destroy
        reset = user.create_password_reset!(last_sent_at: Time.current)
        UserMailer.password_reset(reset).deliver_later
      end
    end

    redirect_to login_path, notice: "If that email is registered, you'll receive a reset link shortly."
  end

  def edit
    @reset = PasswordReset.find_by(token: params[:token])

    if @reset.nil? || @reset.expired?
      redirect_to new_password_reset_path,
                  alert: "That reset link is invalid or has expired. Please request a new one."
      return
    end

    unless @reset.user.internal?
      redirect_to login_path,
                  alert: "Your account uses a social provider to sign in. Please reset your password there."
      nil
    end
  end

  def update
    @reset = PasswordReset.find_by(token: params[:token])

    if @reset.nil? || @reset.expired?
      redirect_to new_password_reset_path, alert: "That reset link is invalid or has expired."
      return
    end

    unless @reset.user.internal?
      redirect_to login_path, alert: "Your account uses a social provider. Please reset your password there."
      return
    end

    user = @reset.user
    password = params[:user][:password]
    confirmation = params[:user][:password_confirmation]

    if password.blank?
      user.errors.add(:password, "can't be blank")
      render :edit, status: :unprocessable_entity
      return
    end

    if password.present? && confirmation.blank?
      @error = "Password confirmation can't be blank"
      render :edit, status: :unprocessable_entity
      return
    end

    if user.update(password: password, password_confirmation: confirmation)
      @reset.destroy
      reset_session
      session[:user_id] = user.id
      redirect_to root_path, notice: "Password updated. You're now logged in."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
