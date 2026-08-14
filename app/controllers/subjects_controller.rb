class SubjectsController < ApplicationController
  before_action :set_class_group, only: :create
  before_action :set_subject, only: %i[show edit update destroy]

  def show
    @exams = @subject.exams.includes(:questions).order(updated_at: :desc)
    @stat_rows = @subject.student_stat_rows
  end

  def create
    @subject = @class_group.subjects.new(subject_params)
    if @subject.save
      redirect_to @class_group, notice: t("subjects.flash.created")
    else
      @students = @class_group.students.active.order(:name)
      @subjects = Subject.where(class_group_id: @class_group.id).includes(:exams).order(:name)
      @student = Current.user.students.new
      render "class_groups/show", status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @subject.update(subject_params)
      redirect_to @subject, notice: t("subjects.flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    class_group = @subject.class_group
    if @subject.destroy
      redirect_to class_group, notice: t("subjects.flash.deleted")
    else
      redirect_to @subject, alert: t("subjects.flash.has_tests")
    end
  end

  private

  def set_class_group
    @class_group = Current.user.class_groups.find(params[:class_group_id])
  end

  def set_subject
    @subject = Current.user.subjects.find(params[:id])
  end

  def subject_params
    params.require(:subject).permit(:name)
  end
end
