class ExamsController < ApplicationController
  before_action :set_subject, only: %i[new create]
  before_action :set_exam, only: %i[show edit update destroy publish close results live]

  def show
    @questions = @exam.questions.with_attached_photo
  end

  def new
    @exam = @subject.exams.new(max_attempts: 1)
  end

  def create
    @exam = @subject.exams.new(exam_params)
    if @exam.save
      redirect_to test_path(@exam), notice: t("exams.flash.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @exam.update(exam_params)
      redirect_to test_path(@exam), notice: t("exams.flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    subject = @exam.subject
    @exam.destroy!
    redirect_to subject_path(subject), notice: t("exams.flash.deleted")
  end

  def publish
    @exam.publish!
    redirect_to test_path(@exam), notice: t("exams.flash.published")
  rescue ActiveRecord::RecordInvalid
    redirect_to test_path(@exam), alert: t("exams.flash.publish_need_question")
  end

  def close
    @exam.close!
    redirect_to test_path(@exam), notice: t("exams.flash.closed")
  end

  def results
    @assignments = @exam.assignments.preload(:student, attempts: :grade).joins(:student).order("students.name")
  end

  def live
    if turbo_frame_request?
      expire_overdue_attempts
      render partial: "exams/live_board", layout: false, locals: LiveBoard.snapshot(@exam)
    end
  end

  private

  def set_subject
    @subject = Current.user.subjects.find(params[:subject_id])
  end

  def set_exam
    @exam = Current.user.exams.find(params[:id])
  end

  # Board accuracy only needs this exam; the whole table is swept by
  # ExpireOverdueAttemptsJob from recurring.yml.
  def expire_overdue_attempts
    AttemptLifecycle.expire_overdue!(@exam.attempts.overdue)
  end

  def exam_params
    permitted = params.require(:exam).permit(
      :title, :description, :time_limit_sec, :max_attempts,
      :available_from, :available_until
    )
    permitted[:available_from] = nil if permitted[:available_from].blank?
    permitted[:available_until] = nil if permitted[:available_until].blank?
    permitted
  end
end
