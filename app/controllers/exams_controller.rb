class ExamsController < ApplicationController
  before_action :set_exam, only: %i[show edit update destroy publish close results live]

  def index
    @exams = Current.user.exams.includes(:questions).order(updated_at: :desc)
  end

  def show
    @questions = @exam.questions
  end

  def new
    @exam = Current.user.exams.new(max_attempts: 1)
  end

  def create
    @exam = Current.user.exams.new(exam_params)
    if @exam.save
      redirect_to test_path(@exam), notice: "Test created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @exam.update(exam_params)
      redirect_to test_path(@exam), notice: "Test updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @exam.destroy!
    redirect_to tests_path, notice: "Test deleted."
  end

  def publish
    @exam.publish!
    redirect_to test_path(@exam), notice: "Test published."
  rescue ActiveRecord::RecordInvalid
    redirect_to test_path(@exam), alert: "Add at least one question before publishing."
  end

  def close
    @exam.close!
    redirect_to test_path(@exam), notice: "Test closed. New starts are blocked."
  end

  def results
    @assignments = @exam.assignments.includes(:student, attempts: :grade).joins(:student).order("students.name")
  end

  def live
    @class_groups = Current.user.class_groups.order(:name)
    @class_group = Current.user.class_groups.find_by(id: params[:class_group_id]) if params[:class_group_id].present?

    if turbo_frame_request?
      ExpireOverdueAttemptsJob.perform_now
      load_live_board
      render partial: "exams/live_board", layout: false
    end
  end

  private

  def set_exam
    @exam = Current.user.exams.find(params[:id])
  end

  def load_live_board
    scope = @exam.assignments.includes(:student, :attempts).joins(:student)
    if @class_group
      scope = scope.joins(student: :class_memberships)
                   .where(class_memberships: { class_group_id: @class_group.id })
                   .distinct
    end

    @assignments = scope.to_a.sort_by { |a| [ a.board_sort_key, a.student.name.to_s.downcase ] }
    @counts = @assignments.group_by(&:board_status).transform_values(&:size)
    @server_time = Time.current
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
