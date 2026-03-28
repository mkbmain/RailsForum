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
  end

  def update
  end
end
