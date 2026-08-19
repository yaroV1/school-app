class AttemptsController < ApplicationController
  before_action :set_attempt
  before_action :ensure_finished, only: :report

  def show
    load_attempt_view
  end

  # The same records the grading page loads, rendered for a parent instead of a
  # teacher: no correct answer, no rubric, no per-answer right-or-wrong mark.
  def report
    load_attempt_view
  end

  def update
    Array(params[:answers]).each do |item|
      answer = @attempt.answers.find_or_initialize_by(question_id: item[:question_id])
      answer.payload = answer.payload.presence || {}
      # Key present but blank means the teacher cleared the field, which drops
      # the override so the auto score applies again. Guarding on the value
      # instead made a score impossible to undo once set.
      answer.teacher_score = item[:teacher_score].presence if item.key?(:teacher_score)
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

  def load_attempt_view
    @exam = @attempt.exam
    @questions = @exam.questions.with_attached_photo
    @answers = @attempt.answers.index_by(&:question_id)
    @grade = @attempt.grade
  end

  # A report for a student still writing would be a moving target, and the score on it
  # would be stale before it reached the printer.
  def ensure_finished
    return unless @attempt.in_progress?

    redirect_to attempt_path(@attempt), alert: t("attempts.flash.report_in_progress")
  end

  def set_attempt
    @attempt = Attempt.joins(assignment: :exam)
                      .where(exams: { teacher_id: Current.user.id })
                      .includes(:answers, :grade, assignment: [ :student, { exam: :questions } ])
                      .find(params[:id])
  end
end
