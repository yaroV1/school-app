class Credits
  PER_TEST = 10

  # The unit of an award is the assignment, not the attempt: the ledger holds what the
  # student's best finalized grade on that test is worth, and each finalization appends only
  # the difference. That is what makes re-finalizing the same grade worth nothing, a better
  # retake worth the improvement, a worse one worth zero, and a grade the teacher lowered a
  # negative correction — without the ledger ever rewriting a row.
  def self.record_award!(grade)
    assignment = grade.attempt.assignment

    # Reading the running total and appending the difference must not interleave with a
    # second "Finalize" click, and deltas rule out the unique index that would otherwise
    # catch it. `default_transaction_mode` is :immediate, so BEGIN takes the database write
    # lock and holds it to COMMIT. Nested inside the caller's transaction this is a no-op and
    # the outer BEGIN is the one that locks; it stays here so a standalone call is safe too.
    CreditEntry.transaction do
      awarded = CreditEntry.where(assignment_id: assignment.id).sum(:amount)
      delta = target_for(assignment) - awarded
      next if delta.zero?

      CreditEntry.create!(student_id: assignment.student_id, assignment: assignment, amount: delta)
    end
  end

  def self.target_for(assignment)
    finalized_grades(assignment).map { |grade| credits_for(grade) }.max || 0
  end

  # A teacher score above the question's points can push a total past the maximum, so the
  # share is clamped rather than trusted.
  def self.credits_for(grade)
    max = grade.max_score.to_d
    return 0 if max <= 0

    (PER_TEST * (grade.total_score || 0).to_d / max).round.clamp(0, PER_TEST)
  end

  def self.finalized_grades(assignment)
    Grade.joins(:attempt)
         .where(attempts: { assignment_id: assignment.id }, finalized_by_teacher: true)
  end
  private_class_method :finalized_grades
end
