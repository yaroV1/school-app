class ClassMembership < ApplicationRecord
  belongs_to :class_group
  belongs_to :student

  validates :student_id, uniqueness: { scope: :class_group_id }
end
