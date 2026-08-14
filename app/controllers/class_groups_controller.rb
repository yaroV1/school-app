class ClassGroupsController < ApplicationController
  before_action :set_class_group, only: %i[show edit update destroy remove_member]

  def index
    @class_groups = Current.user.class_groups.includes(:students, :subjects).order(:name)
  end

  def show
    @students = @class_group.students.active.order(:name)
    @subjects = @class_group.subjects.includes(:exams).order(:name).to_a
    @student = Current.user.students.new
    @subject = Subject.new
  end

  def new
    @class_group = Current.user.class_groups.new
  end

  def create
    @class_group = Current.user.class_groups.new(class_group_params)
    if @class_group.save
      redirect_to @class_group, notice: t("classes.flash.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @class_group.update(class_group_params)
      redirect_to @class_group, notice: t("classes.flash.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @class_group.destroy
      redirect_to class_groups_path, notice: t("classes.flash.deleted")
    else
      redirect_to @class_group, alert: t("classes.flash.has_subjects")
    end
  end

  def remove_member
    membership = @class_group.class_memberships.find_by!(student_id: params[:student_id])
    membership.destroy!
    redirect_to @class_group, notice: t("classes.flash.member_removed")
  end

  private

  def set_class_group
    @class_group = Current.user.class_groups.find(params[:id])
  end

  def class_group_params
    params.require(:class_group).permit(:name)
  end
end
