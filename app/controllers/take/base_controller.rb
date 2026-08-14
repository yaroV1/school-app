module Take
  class BaseController < ApplicationController
    allow_unauthenticated_access
    layout "student"

    before_action :set_assignment

    private

    def set_assignment
      @assignment = Assignment.find_by!(access_token: params[:token])
      @exam = @assignment.exam
      @student = @assignment.student
    end
  end
end
