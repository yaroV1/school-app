class AddClassGroupToExams < ActiveRecord::Migration[8.1]
  def up
    add_reference :exams, :class_group, foreign_key: true

    Exam.reset_column_information
    Exam.find_each do |exam|
      teacher = User.find(exam.teacher_id)
      group_ids = Assignment.where(exam_id: exam.id)
                            .joins(student: :class_memberships)
                            .distinct
                            .pluck("class_memberships.class_group_id")
      group_id = if group_ids.size == 1
        group_ids.first
      else
        teacher.class_groups.order(:id).first&.id ||
          ClassGroup.create!(teacher: teacher, name: "Клас").id
      end
      exam.update_column(:class_group_id, group_id)
    end

    change_column_null :exams, :class_group_id, false
  end

  def down
    remove_reference :exams, :class_group, foreign_key: true
  end
end
