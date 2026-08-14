class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :students, foreign_key: :teacher_id, dependent: :destroy, inverse_of: :teacher
  has_many :class_groups, foreign_key: :teacher_id, dependent: :destroy, inverse_of: :teacher
  has_many :subjects, through: :class_groups
  has_many :exams, foreign_key: :teacher_id, dependent: :destroy, inverse_of: :teacher

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
end
