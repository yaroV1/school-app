class TelegramConnectionsController < ApplicationController
  before_action :set_student

  def create
    @student.with_lock do
      if @student.telegram_pending_chat_id.present? && @student.telegram_pending_chat_id.to_s == params[:chat_id].to_s && !@student.archived?
        @student.update!(telegram_chat_id: @student.telegram_pending_chat_id,
          telegram_pending_chat_id: nil, telegram_pending_name: nil)
      end
    end
    redirect_to @student
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to @student, alert: t("telegram.connection.already_used")
  end

  def destroy
    @student.update!(telegram_chat_id: nil, telegram_pending_chat_id: nil, telegram_pending_name: nil)
    redirect_to @student
  end

  private

  def set_student
    @student = Current.user.students.find(params[:student_id])
  end
end
