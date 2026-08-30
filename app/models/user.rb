class User < ApplicationRecord
  # A teacher account owns every class, test and grade under it, and there is no second factor
  # behind it. has_secure_password enforces a ceiling (72 bytes) but no floor.
  MINIMUM_PASSWORD_LENGTH = 12

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :students, foreign_key: :teacher_id, dependent: :destroy, inverse_of: :teacher
  has_many :class_groups, foreign_key: :teacher_id, dependent: :destroy, inverse_of: :teacher
  has_many :subjects, through: :class_groups
  has_many :exams, foreign_key: :teacher_id, dependent: :destroy, inverse_of: :teacher

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  # allow_nil, not presence: has_secure_password already refuses a record with no digest, and
  # every update that leaves the password alone reads it back as nil.
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true
end
