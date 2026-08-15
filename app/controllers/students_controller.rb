class StudentsController < ApplicationController
  before_action :set_class_group, only: :create
  before_action :set_student, only: %i[show edit update archive unarchive]

  def show
    @attempts = @student.attempts.includes(:exam, :grade).order(started_at: :desc)
  end

  def create
    @student = Current.user.students.new(student_params)
    if @student.save
      @class_group.add_student!(@student)
      redirect_to students_class_group_path(@class_group), notice: t("students.flash.created")
    else
      @students = @class_group.students.active.order(:name)
      render "class_groups/students", status: :unprocessable_entity
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
    redirect_back_or_to class_groups_path, notice: t("students.flash.archived")
  end

  def unarchive
    @student.unarchive!
    redirect_back_or_to @student, notice: t("students.flash.restored")
  end

  private

  def set_class_group
    @class_group = Current.user.class_groups.find(params[:class_group_id])
  end

  def set_student
    @student = Current.user.students.find(params[:id])
  end

  def student_params
    params.require(:student).permit(:name, :email)
  end
end
