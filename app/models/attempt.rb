class Attempt < ApplicationRecord
  belongs_to :assignment
  has_one :exam, through: :assignment
  has_one :student, through: :assignment
  has_many :answers, dependent: :destroy
  has_one :grade, dependent: :destroy

  enum :status, { in_progress: 0, submitted: 1, expired: 2, abandoned: 3 }, validate: true

  validates :attempt_no, uniqueness: { scope: :assignment_id }
  validates :started_at, :last_activity_at, presence: true

  scope :overdue, -> {
    in_progress.where.not(deadline_at: nil).where("deadline_at < ?", Time.current)
  }

  def past_deadline?(now = Time.current)
    deadline_at.present? && now > deadline_at
  end

  def seconds_remaining(now = Time.current)
    return nil if deadline_at.blank?

    [ (deadline_at - now).to_i, 0 ].max
  end

  def touch_activity!
    update!(last_activity_at: Time.current)
  end
end
