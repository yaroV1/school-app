class Assignment < ApplicationRecord
  belongs_to :exam
  belongs_to :student
  has_many :attempts, dependent: :destroy
  has_many :credit_entries, dependent: :destroy

  validates :access_token, presence: true, uniqueness: true
  validates :student_id, uniqueness: { scope: :exam_id }

  before_validation :ensure_access_token, on: :create

  scope :active, -> { where(revoked_at: nil) }

  BOARD_SORT = {
    "in_progress" => 0,
    "not_started" => 1,
    "submitted" => 2,
    "expired" => 3,
    "revoked" => 4
  }.freeze

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def regenerate_token!
    update!(access_token: TokenGenerator.call, revoked_at: nil)
  end

  def access_url(base_url:)
    "#{base_url}/t/#{access_token}"
  end

  def attempts_used
    attempts.size
  end

  def in_progress_attempt
    if attempts.loaded?
      attempts.select(&:in_progress?).max_by(&:attempt_no)
    else
      attempts.in_progress.order(:attempt_no).last
    end
  end

  def latest_attempt
    if attempts.loaded?
      attempts.max_by(&:attempt_no)
    else
      attempts.order(attempt_no: :desc).first
    end
  end

  def latest_finished_attempt
    if attempts.loaded?
      attempts.select { |attempt| attempt.submitted? || attempt.expired? }.max_by(&:attempt_no)
    else
      attempts.where(status: %i[submitted expired]).order(attempt_no: :desc).first
    end
  end

  def can_start?
    return false if revoked?
    return false unless exam.published?
    return true if in_progress_attempt.present?
    return false unless exam.within_availability_window?

    attempts_used < exam.max_attempts
  end

  def board_status
    return "revoked" if revoked?

    attempt = latest_attempt
    return "not_started" if attempt.nil?
    return "in_progress" if attempt.in_progress?
    return "submitted" if attempt.submitted?
    return "expired" if attempt.expired?

    attempt.status
  end

  def board_sort_key
    BOARD_SORT.fetch(board_status, 99)
  end

  private

  def ensure_access_token
    self.access_token ||= TokenGenerator.call
  end
end
