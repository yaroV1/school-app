class QuestionSanitizer
  def self.for_student(question)
    {
      id: question.id,
      question_type: question.question_type,
      prompt: question.prompt,
      points: question.points,
      position: question.position,
      options: question.mcq? ? question.student_facing_options : nil
    }
  end
end
