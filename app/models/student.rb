class Student < ApplicationRecord
  belongs_to :teacher, class_name: "User", inverse_of: :students
  has_many :class_memberships, dependent: :destroy
  has_many :class_groups, through: :class_memberships
  has_many :assignments, dependent: :destroy
  has_many :attempts, through: :assignments

  validates :name, presence: true

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end
end
