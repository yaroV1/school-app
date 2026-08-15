class LiveBoard
  def self.snapshot(exam)
    new(exam).snapshot
  end

  def self.replace(exam)
    new(exam).replace
  end

  def initialize(exam)
    @exam = exam
  end

  def snapshot
    assignments = Assignment.where(exam_id: @exam.id).preload(:student, :attempts).to_a
    assignments.sort_by! { |assignment| [ assignment.board_sort_key, assignment.student.name.to_s.downcase ] }

    {
      exam: @exam,
      assignments: assignments,
      counts: assignments.group_by(&:board_status).transform_values(&:size),
      server_time: Time.current
    }
  end

  def replace
    Turbo::StreamsChannel.broadcast_replace_to(
      @exam,
      :live_board,
      target: "live_board",
      partial: "exams/live_board",
      locals: snapshot
    )
  end
end
