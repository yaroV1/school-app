class TelegramDeliveryJob < ApplicationJob
  def perform(assignment_id, request_id)
    TelegramDelivery.deliver(assignment_id, request_id)
  end
end
