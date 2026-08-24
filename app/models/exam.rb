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

  def duplicate!
    transaction do
      copy = dup
      copy.assign_attributes(
        title: I18n.t("exams.duplicate.copy_title", title: title),
        status: :draft,
        available_from: nil,
        available_until: nil
      )
      copy.save!
      questions.each { |question| duplicate_question(question, copy) }
      copy
    end
  end

  def questions_editable?
    draft?
  end

  def wording_editable?
    draft? || published?
  end

  def max_score
    if questions.loaded?
      questions.sum(&:points)
    else
      questions.sum(:points)
    end
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

  def duplicate_question(question, copy)
    duplicated = question.dup
    duplicated.exam = copy
    duplicated.save!
    return unless question.photo.attached?

    # The upload is deferred to the transaction's commit, so the bytes must sit in an IO
    # that is still open then — a Blob#open tempfile is already closed at that point.
    duplicated.photo.attach(
      io: StringIO.new(question.photo.download),
      filename: question.photo.filename,
      content_type: question.photo.content_type
    )
  end

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
