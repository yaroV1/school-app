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
    params.require(:question).permit(:question_type, :prompt, :points, :position)
  end

  def apply_config!(question)
    case question.question_type
    when "mcq"
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
    else
      question.config = {
        "rubric" => params.dig(:question, :rubric).to_s,
        "model_answer" => params.dig(:question, :model_answer).to_s
      }
    end
  end
end
