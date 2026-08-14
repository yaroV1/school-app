class Answer < ApplicationRecord
  belongs_to :attempt
  belongs_to :question

  validates :question_id, uniqueness: { scope: :attempt_id }

  def scored?
    teacher_score.present? || auto_score.present?
  end

  def effective_score
    teacher_score.presence || auto_score
  end

  def text_response
    payload["text"]
  end

  def option_id
    payload["option_id"]
  end

  def order_ids
    Array(payload["order"]).map(&:to_s)
  end

  def pairs
    (payload["pairs"] || {}).stringify_keys
  end
end

