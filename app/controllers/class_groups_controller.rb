class ClassGroupsController < ApplicationController
  before_action :set_class_group, only: %i[show edit update destroy members]

  def index
    @class_groups = Current.user.class_groups.includes(:students).order(:name)
  end

  def show
    @students = Current.user.students.active.order(:name)
  end

  def new
    @class_group = Current.user.class_groups.new
  end

  def create
    @class_group = Current.user.class_groups.new(class_group_params)
    if @class_group.save
      redirect_to @class_group, notice: "Class created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @class_group.update(class_group_params)
      redirect_to @class_group, notice: "Class updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @class_group.destroy!
    redirect_to class_groups_path, notice: "Class deleted."
  end

  def members
    @class_group.replace_members!(params[:student_ids])
    redirect_to @class_group, notice: "Members updated."
  end

  private

  def set_class_group
    @class_group = Current.user.class_groups.find(params[:id])
  end

  def class_group_params
    params.require(:class_group).permit(:name)
  end
end
