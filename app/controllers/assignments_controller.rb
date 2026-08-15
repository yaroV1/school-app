class AssignmentsController < ApplicationController
  before_action :set_exam, only: %i[index create manage bulk_revoke]
  before_action :set_assignment, only: %i[revoke regenerate_token]

  def index
    redirect_to manage_test_assignments_path(@exam)
  end

  def manage
    @assignments = @exam.assignments.preload(:student, :attempts).joins(:student).order("students.name")
    @students = @exam.class_group.students.active.order(:name)
  end

  def create
    student_ids = resolve_student_ids
    created = 0

    student_ids.each do |student_id|
      assignment = @exam.assignments.find_or_initialize_by(student_id: student_id)
      if assignment.new_record?
        assignment.save!
        created += 1
      elsif assignment.revoked?
        assignment.regenerate_token!
        created += 1
      end
    end

    LiveBoard.replace(@exam) if created.positive?
    redirect_to manage_test_assignments_path(@exam), notice: t("exams.flash.assigned", count: created)
  end

  def bulk_revoke
    ids = Array(params[:assignment_ids]).map(&:to_i)
    scope = @exam.assignments.active.where(id: ids)
    count = 0
    scope.find_each do |assignment|
      assignment.revoke!
      count += 1
    end
    LiveBoard.replace(@exam) if count.positive?
    redirect_to manage_test_assignments_path(@exam), notice: t("exams.flash.revoked_many", count: count)
  end

  def revoke
    @assignment.revoke!
    LiveBoard.replace(@assignment.exam)
    redirect_to manage_test_assignments_path(@assignment.exam), notice: t("exams.flash.revoked")
  end

  def regenerate_token
    @assignment.regenerate_token!
    LiveBoard.replace(@assignment.exam)
    redirect_to manage_test_assignments_path(@assignment.exam), notice: t("exams.flash.regenerated")
  end

  private

  def set_exam
    @exam = Current.user.exams.find(params[:exam_id] || params[:test_id])
  end

  def set_assignment
    @assignment = Assignment.joins(:exam).where(exams: { teacher_id: Current.user.id }).find(params[:id])
  end

  def resolve_student_ids
    class_student_ids = @exam.class_group.students.active.pluck(:id)
    if params[:assign_class].present?
      class_student_ids
    else
      ids = Array(params[:student_ids]).map(&:to_i)
      class_student_ids & ids
    end
  end
end
