class AttemptsController < ApplicationController
  before_action :set_attempt

  def show
    @exam = @attempt.exam
    @questions = @exam.questions
    @answers = @attempt.answers.index_by(&:question_id)
    @grade = @attempt.grade
  end

  def update
    Array(params[:answers]).each do |item|
      answer = @attempt.answers.find_or_initialize_by(question_id: item[:question_id])
      answer.payload = answer.payload.presence || {}
      answer.teacher_score = item[:teacher_score] if item[:teacher_score].present?
      answer.teacher_comment = item[:teacher_comment] if item.key?(:teacher_comment)
      answer.save!
    end

    grade = @attempt.grade || @attempt.build_grade(max_score: @attempt.exam.max_score)
    grade.teacher_comment = params[:teacher_comment] if params.key?(:teacher_comment)
    grade.total_score = Scoring.partial_total(@attempt)
    grade.save!

    if params[:finalize].present?
      unless Scoring.ready_to_finalize?(@attempt)
        return redirect_to attempt_path(@attempt), alert: t("attempts.flash.need_scores")
      end

      grade.finalize!
      redirect_to attempt_path(@attempt), notice: t("attempts.flash.finalized")
    else
      redirect_to attempt_path(@attempt), notice: t("attempts.flash.saved")
    end
  end

  private

  def set_attempt
    @attempt = Attempt.joins(assignment: :exam)
                      .where(exams: { teacher_id: Current.user.id })
                      .includes(:answers, :grade, assignment: [ :student, { exam: :questions } ])
                      .find(params[:id])
  end
end
