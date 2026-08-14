class QuestionsController < ApplicationController
  before_action :set_exam
  before_action :ensure_editable
  before_action :set_question, only: %i[update destroy]

  def create
    @question = @exam.questions.new(question_params)
    @question.position = (@exam.questions.maximum(:position) || -1) + 1
    apply_config!(@question)

    if @question.save
      redirect_to test_path(@exam), notice: t("exams.flash.question_added")
    else
      redirect_to test_path(@exam), alert: @question.errors.full_messages.to_sentence
    end
  end

  def update
    @question.assign_attributes(question_params)
    apply_config!(@question)

    if @question.save
      redirect_to test_path(@exam), notice: t("exams.flash.question_updated")
    else
      redirect_to test_path(@exam), alert: @question.errors.full_messages.to_sentence
    end
  end

  def destroy
    @question.destroy!
    redirect_to test_path(@exam), notice: t("exams.flash.question_removed")
  end

  private

  def set_exam
    @exam = Current.user.exams.find(params[:test_id] || params[:exam_id])
  end

  def set_question
    @question = @exam.questions.find(params[:id])
  end

  def ensure_editable
    return if @exam.questions_editable?

    redirect_to test_path(@exam), alert: t("exams.flash.questions_locked")
  end

  def question_params
    params.require(:question).permit(:question_type, :prompt, :points, :position, :photo)
  end

  def apply_config!(question)
    case question.question_type
    when "mcq"
      apply_mcq_config!(question)
    when "ordering"
      apply_ordering_config!(question)
    when "matching"
      apply_matching_config!(question)
    when "source"
      apply_source_config!(question)
    else
      question.config = {
        "rubric" => params.dig(:question, :rubric).to_s,
        "model_answer" => params.dig(:question, :model_answer).to_s
      }
    end
  end

  def apply_mcq_config!(question)
    raw = params.dig(:question, :options) || {}
    correct_index = params.dig(:question, :correct_index).to_s
    options = []
    raw.each do |index, opt|
      text = opt[:text].to_s.strip
      next if text.blank?

      options << {
        "id" => opt[:id].presence || SecureRandom.hex(4),
        "text" => text,
        "is_correct" => index.to_s == correct_index
      }
    end
    options.first["is_correct"] = true if options.any? && options.none? { |o| o["is_correct"] }
    if (first_correct = options.index { |o| o["is_correct"] })
      options.each_with_index { |o, i| o["is_correct"] = i == first_correct }
    end
    question.config = { "options" => options }
  end

  def apply_ordering_config!(question)
    items = []
    raw = params.dig(:question, :items) || {}
    raw.each do |_index, item|
      text = item[:text].to_s.strip
      next if text.blank?

      items << {
        "id" => item[:id].presence || SecureRandom.hex(4),
        "text" => text
      }
    end
    question.config = { "items" => items }
  end

  def apply_matching_config!(question)
    left = []
    right = []
    pairs = {}
    raw = params.dig(:question, :pairs) || {}
    raw.each do |_index, row|
      left_text = row[:left].to_s.strip
      right_text = row[:right].to_s.strip
      next if left_text.blank? || right_text.blank?

      left_id = row[:left_id].presence || "l#{SecureRandom.hex(3)}"
      right_id = row[:right_id].presence || "r#{SecureRandom.hex(3)}"
      left << { "id" => left_id, "text" => left_text }
      right << { "id" => right_id, "text" => right_text }
      pairs[left_id] = right_id
    end
    question.config = { "left" => left, "right" => right, "pairs" => pairs }
  end

  def apply_source_config!(question)
    question.config = {
      "source" => params.dig(:question, :source).to_s,
      "rubric" => params.dig(:question, :rubric).to_s,
      "model_answer" => params.dig(:question, :model_answer).to_s
    }
  end
end
