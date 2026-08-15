require "test_helper"

class ExamTest < ActiveSupport::TestCase
  test "max_score uses preloaded questions" do
    exam = create_exam!(users(:one))
    exam.questions.create!(question_type: :short_text, prompt: "A", points: 2, position: 0, config: {})
    exam.questions.create!(question_type: :short_text, prompt: "B", points: 3, position: 1, config: {})

    loaded = Exam.preload(:questions).find(exam.id)
    assert_no_queries { assert_equal 5, loaded.max_score }
  end
end
