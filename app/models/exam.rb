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
  validate :subject_change_requires_no_assignments, on: :update

  before_validation :assign_teacher_from_subject

  def publish!
    raise ActiveRecord::RecordInvalid, self if questions.none?

    update!(status: :published)
  end

  def close!
    update!(status: :closed)
  end

  def duplicate!(target_subject = subject)
    # Photo bytes are read before BEGIN: the immediate-mode transaction holds the database
    # write lock from start to commit, and a multi-megabyte blob download inside it would
    # stall student autosaves for the duration.
    downloaded = questions.with_attached_photo.map do |question|
      [ question, question.photo.attached? ? question.photo.download : nil ]
    end
    transaction do
      copy = dup
      copy.assign_attributes(
        subject: target_subject,
        title: I18n.t("exams.duplicate.copy_title", title: title),
        status: :draft,
        available_from: nil,
        available_until: nil
      )
      copy.save!
      downloaded.each { |question, photo_bytes| duplicate_question(question, photo_bytes, copy) }
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

  # The upload is deferred to the transaction's commit, so the bytes must sit in an IO
  # that is still open then — a Blob#open tempfile is already closed at that point.
  # Attaching before save! keeps the photo inside the copy's validation: attach on an
  # already-persisted row saves with save, not save!, and a photo the copy cannot accept
  # would commit the copy silently photo-less instead of rolling it back.
  def duplicate_question(question, photo_bytes, copy)
    duplicated = question.dup
    duplicated.exam = copy
    if photo_bytes
      duplicated.photo.attach(
        io: StringIO.new(photo_bytes),
        filename: question.photo.filename,
        content_type: question.photo.content_type
      )
    end
    duplicated.save!
  end

  def assign_teacher_from_subject
    self.teacher = subject.class_group.teacher if subject
  end

  def subject_belongs_to_teacher
    return if subject.blank? || teacher.blank?
    return if subject.class_group.teacher_id == teacher_id

    errors.add(:subject, :invalid)
  end

  # Any assignment, revoked included, ties students, tokens and attempt history to the
  # current class — a moved history would lie in the target subject's stats.
  def subject_change_requires_no_assignments
    return unless subject_id_changed? && assignments.exists?

    errors.add(:subject, :has_assignments)
  end

  def availability_window_order
    return if available_from.blank? || available_until.blank?
    return if available_until > available_from

    errors.add(:available_until, :after_available_from)
  end
end
