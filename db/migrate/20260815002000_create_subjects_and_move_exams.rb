class CreateSubjectsAndMoveExams < ActiveRecord::Migration[8.1]
  def up
    create_table :subjects do |t|
      t.references :class_group, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :subjects, %i[class_group_id name], unique: true

    add_reference :exams, :subject, foreign_key: true

    Exam.reset_column_information
    Exam.where.not(class_group_id: nil).distinct.pluck(:class_group_id).each do |group_id|
      subject_id = Subject.create!(class_group_id: group_id, name: "Предмет").id
      Exam.where(class_group_id: group_id).update_all(subject_id: subject_id)
    end

    change_column_null :exams, :subject_id, false
    remove_reference :exams, :class_group, foreign_key: true
  end

  def down
    add_reference :exams, :class_group, foreign_key: true

    Exam.reset_column_information
    Exam.find_each do |exam|
      exam.update_column(:class_group_id, Subject.find(exam.subject_id).class_group_id)
    end

    change_column_null :exams, :class_group_id, false
    remove_reference :exams, :subject, foreign_key: true
    drop_table :subjects
  end
end
