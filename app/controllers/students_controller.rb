class StudentsController < ApplicationController
  before_action :set_student, only: %i[show edit update archive unarchive]

  def index
    @students = Current.user.students.order(:name)
    @students = @students.active unless params[:include_archived] == "1"
  end

  def show
    @assignments = @student.assignments.includes(:exam, attempts: :grade).order(created_at: :desc)
    @attempts = Attempt.joins(:assignment).where(assignments: { student_id: @student.id })
                       .includes(:grade, assignment: :exam)
                       .order(started_at: :desc)
  end

  def new
    @student = Current.user.students.new
  end

  def create
    @student = Current.user.students.new(student_params)
    if @student.save
      redirect_to students_path, notice: t("students.flash.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @student.update(student_params)
      redirect_to @student, notice: t("students.flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    @student.archive!
    redirect_to students_path, notice: t("students.flash.archived")
  end

  def unarchive
    @student.unarchive!
    redirect_to students_path, notice: t("students.flash.restored")
  end

  private

  def set_student
    @student = Current.user.students.find(params[:id])
  end

  def student_params
    params.require(:student).permit(:name, :email)
  end
end
