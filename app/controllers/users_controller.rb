class UsersController < ApplicationController
  def new
    redirect_to(root_path) and return if logged_in?
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.provider_id = Provider::INTERNAL
    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to root_path, notice: "Welcome, #{@user.name}!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :name, :password, :password_confirmation)
  end
end
