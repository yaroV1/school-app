class Exam < ApplicationRecord
  belongs_to :teacher, class_name: "User", inverse_of: :exams
  belongs_to :subject, inverse_of: :exams
  has_one :class_group, through: :subject
  has_many :questions, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :exam
  has_many :assignments, dependent: :destroy
  has_many :attempts, through: :assignments

  enum :status, { draft: 0, published: 1, closed: 2 }, validate: true

  validates :title, presence: true
  validates :max_attempts, numericality: { only_integer: true, greater_than: 0 }
  validates :time_limit_sec, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :availability_window_order
  validate :subject_belongs_to_teacher

  before_validation :assign_teacher_from_subject

  def publish!
    raise ActiveRecord::RecordInvalid, self if questions.none?

    update!(status: :published)
  end

  def close!
    update!(status: :closed)
  end

  def questions_editable?
    draft?
  end

  def max_score
    questions.sum(:points)
  end

  def within_availability_window?(now = Time.current)
    return false if available_from.present? && now < available_from
    return false if available_until.present? && now > available_until

    true
  end

  def availability_status(now = Time.current)
    return :not_yet_open if available_from.present? && now < available_from
    return :closed_window if available_until.present? && now > available_until

    :open
  end

  private

  def assign_teacher_from_subject
    self.teacher = subject.class_group.teacher if subject
  end

  def subject_belongs_to_teacher
    return if subject.blank? || teacher.blank?
    return if subject.class_group.teacher_id == teacher_id

    errors.add(:subject, :invalid)
  end

  def availability_window_order
    return if available_from.blank? || available_until.blank?
    return if available_until > available_from

    errors.add(:available_until, :after_available_from)
  end
end
