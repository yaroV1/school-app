class TelegramDeliveriesController < ApplicationController
  def create
    exam = Current.user.exams.find(params[:test_id])
    unless TelegramBot.configured? && exam.published?
      return redirect_to manage_test_assignments_path(exam), alert: t("telegram.delivery.unavailable")
    end

    assignments = exam.assignments.active
    assignments = assignments.where(id: Array(params[:assignment_ids])) unless params[:send_all] == "1"
    count = 0
    assignments.find_each do |assignment|
      count += 1 if TelegramDelivery.enqueue(assignment, wait: count.seconds)
    end
    redirect_to manage_test_assignments_path(exam), notice: t("telegram.delivery.queued_count", count: count)
  end
end
