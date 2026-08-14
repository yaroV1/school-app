class QuestionSanitizer
  def self.for_student(question, seed: nil)
    seed = seed.presence || question.id
    payload = {
      id: question.id,
      question_type: question.question_type,
      prompt: question.prompt,
      points: question.points,
      position: question.position,
      options: nil,
      items: nil,
      left: nil,
      right: nil
    }

    if question.mcq?
      payload[:options] = question.student_facing_options
    elsif question.ordering?
      payload[:items] = question.shuffled_items(seed)
    elsif question.matching?
      payload[:left] = question.student_facing_left
      payload[:right] = question.shuffled_right_items(seed)
    elsif question.source?
      payload[:source] = question.source_text
    end

    payload
  end
end
