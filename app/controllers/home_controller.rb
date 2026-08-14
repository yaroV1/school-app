class HomeController < ApplicationController
  def index
    redirect_to class_groups_path
  end
end
