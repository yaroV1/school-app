class HomeController < ApplicationController
  def index
    redirect_to tests_path
  end
end
