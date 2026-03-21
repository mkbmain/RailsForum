class Admin::BaseController < ApplicationController
  before_action :require_login
  before_action :require_moderator
  layout "admin"
end
