class ExamsController < ApplicationController
  before_action :set_subject, only: %i[new create]
  before_action :set_exam, only: %i[show edit update destroy publish close results live print print_key]

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
    respond_to do |format|
      format.html
      format.csv { send_csv("#{@exam.title}.csv", results_csv_headers, results_csv_rows) }
    end
  end

  def live
    if turbo_frame_request?
      expire_overdue_attempts
      render partial: "exams/live_board", layout: false, locals: LiveBoard.snapshot(@exam)
    end
  end

  # Kernel#print is private, so a public action of the same name shadows nothing
  # Rails or Ruby calls on the controller.
  def print
    @questions = @exam.questions.with_attached_photo
  end

  # A separate action rendering a separate template, rather than a flag on #print:
  # the student sheet then has no branch that could be inverted into printing the key.
  def print_key
    @questions = @exam.questions.with_attached_photo
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

  def results_csv_headers
    [
      t("exams.assign.student"),
      t("exams.results.latest_status"),
      t("attempts.history.started"),
      t("exams.results.submitted"),
      t("exams.results.score"),
      t("exams.results.max_score")
    ]
  end

  def results_csv_rows
    @assignments.map do |assignment|
      attempt = assignment.latest_attempt
      grade = attempt&.grade
      [
        assignment.student.name,
        attempt ? t("statuses.#{attempt.status}") : t("statuses.not_started"),
        csv_time(attempt&.started_at),
        csv_time(attempt&.submitted_at),
        csv_decimal(grade&.total_score),
        grade ? csv_decimal(grade.max_score) : ""
      ]
    end
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
