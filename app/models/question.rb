class Question < ApplicationRecord
  belongs_to :exam, inverse_of: :questions
  has_many :answers, dependent: :destroy

  enum :question_type, { mcq: 0, short_text: 1, open: 2 }, validate: true

  validates :prompt, presence: true
  validates :points, numericality: { only_integer: true, greater_than: 0 }
  validate :mcq_has_correct_option

  def options
    Array(config["options"])
  end

  def rubric
    config["rubric"]
  end

  def model_answer
    config["model_answer"]
  end

  def correct_option_id
    options.find { |o| o["is_correct"] }&.dig("id")
  end

  def student_facing_options
    options.map { |o| o.slice("id", "text") }
  end

  private

  def mcq_has_correct_option
    return unless mcq?

    if options.blank?
    errors.add(:config, :blank_options)
      return
    end

    correct = options.count { |o| o["is_correct"] }
    errors.add(:config, :one_correct) unless correct == 1
  end
end
