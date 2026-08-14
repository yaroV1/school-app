class Grade < ApplicationRecord
  belongs_to :attempt

  validates :max_score, presence: true

  def incomplete?
    !finalized_by_teacher?
  end

  def finalize!
    update!(
      finalized_by_teacher: true,
      finalized_at: Time.current,
      total_score: Scoring.total_for(attempt)
    )
  end
end
