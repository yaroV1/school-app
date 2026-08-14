class Subject < ApplicationRecord
  StudentStat = Struct.new(:student, :assigned, :finished, :average_percent, :last_activity_at, keyword_init: true)

  belongs_to :class_group, inverse_of: :subjects
  has_many :exams, dependent: :restrict_with_error, inverse_of: :subject

  validates :name, presence: true, uniqueness: { scope: :class_group_id }

  def student_stat_rows
    tracked = exams.where(status: %i[published closed]).includes(assignments: { attempts: :grade }).to_a
    assignments_by_student_id = Hash.new { |h, k| h[k] = [] }
    tracked.each do |exam|
      exam.assignments.each do |assignment|
        next if assignment.revoked?

        assignments_by_student_id[assignment.student_id] << assignment
      end
    end

    class_group.students.active.order(:name).map do |student|
      assigned = assignments_by_student_id[student.id]
      latest = assigned.filter_map(&:latest_attempt)
      percents = latest.filter_map { |attempt| percent_for(attempt) }

      StudentStat.new(
        student: student,
        assigned: assigned.size,
        finished: latest.count { |attempt| attempt.submitted? || attempt.expired? },
        average_percent: percents.any? ? (percents.sum / percents.size).round : nil,
        last_activity_at: latest.map { |attempt| attempt.submitted_at || attempt.last_activity_at }.compact.max
      )
    end
  end

  private

  def percent_for(attempt)
    grade = attempt.grade
    return if grade.nil? || grade.total_score.nil?

    max = grade.max_score.to_d
    return if max <= 0

    grade.total_score.to_d / max * 100
  end
end
