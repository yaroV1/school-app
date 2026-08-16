require "test_helper"

class ExamTest < ActiveSupport::TestCase
  test "max_score uses preloaded questions" do
    exam = create_exam!(users(:one))
    exam.questions.create!(question_type: :short_text, prompt: "A", points: 2, position: 0, config: {})
    exam.questions.create!(question_type: :short_text, prompt: "B", points: 3, position: 1, config: {})

    loaded = Exam.preload(:questions).find(exam.id)
    assert_no_queries { assert_equal 5, loaded.max_score }
  end

  test "structure is editable in draft alone, wording until the test is closed" do
    exam = create_exam!(users(:one))
    exam.questions.create!(question_type: :short_text, prompt: "A", points: 1, position: 0, config: {})

    assert exam.draft?
    assert exam.questions_editable?
    assert exam.wording_editable?

    exam.publish!
    assert_not exam.questions_editable?
    assert exam.wording_editable?

    exam.close!
    assert_not exam.questions_editable?
    assert_not exam.wording_editable?
  end

  test "wording_editable? denies a status it was never taught" do
    assert_not Exam.new(status: nil).wording_editable?, "an unset status must not grant wording writes"
  end
end
