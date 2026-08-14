class ClassGroup < ApplicationRecord
  belongs_to :teacher, class_name: "User", inverse_of: :class_groups
  has_many :class_memberships, dependent: :destroy
  has_many :students, through: :class_memberships

  validates :name, presence: true

  def replace_members!(student_ids)
    ids = Array(student_ids).map(&:to_i).uniq
    owned_ids = teacher.students.where(id: ids).pluck(:id)
    transaction do
      class_memberships.where.not(student_id: owned_ids).delete_all
      owned_ids.each do |student_id|
        class_memberships.find_or_create_by!(student_id: student_id)
      end
    end
  end
end
