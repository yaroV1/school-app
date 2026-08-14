require "test_helper"

class MvpFlowTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
  end

  test "teacher assigns links and student submits mcq short and open" do
    sign_in_as @teacher

    post students_url, params: { student: { name: "Sam" } }
    student = Student.order(:id).last

    post class_groups_url, params: { class_group: { name: "10-A" } }
    group = ClassGroup.order(:id).last
    put members_class_group_url(group), params: { student_ids: [ student.id ] }

    post tests_url, params: { exam: { title: "Unit 1", max_attempts: 1, time_limit_sec: 300 } }
    exam = Exam.order(:id).last

    post test_questions_url(exam), params: {
      question: {
        question_type: "mcq",
        prompt: "2+2?",
        points: 1,
        correct_index: "1",
        options: {
          "0" => { text: "3" },
          "1" => { text: "4" }
        }
      }
    }
    post test_questions_url(exam), params: {
      question: { question_type: "short_text", prompt: "Sky?", points: 1, rubric: "" }
    }
    post test_questions_url(exam), params: {
      question: { question_type: "open", prompt: "Essay", points: 2, rubric: "" }
    }
    post test_questions_url(exam), params: {
      question: {
        question_type: "ordering",
        prompt: "Order events",
        points: 2,
        items: {
          "0" => { text: "First" },
          "1" => { text: "Second" },
          "2" => { text: "Third" }
        }
      }
    }
    post test_questions_url(exam), params: {
      question: {
        question_type: "matching",
        prompt: "Match facts",
        points: 3,
        pairs: {
          "0" => { left: "Churchill", right: "UK" },
          "1" => { left: "Roosevelt", right: "USA" },
          "2" => { left: "Stalin", right: "USSR" }
        }
      }
    }

    post publish_test_url(exam)
    exam.reload
    assert exam.published?

    post test_assignments_url(exam), params: { student_ids: [ student.id ] }
    assignment = exam.assignments.find_by!(student: student)
    token = assignment.access_token

    delete session_url

    get student_portal_url(token: token)
    assert_response :success

    post student_start_url(token: token)
    follow_redirect!
    assert_response :success

    attempt = assignment.attempts.last
    mcq, short_q, open_q, ordering, matching = exam.questions.order(:position)

    put student_answers_url(token: token), params: {
      attempt_id: attempt.id,
      answers: [
        { question_id: mcq.id, payload: { option_id: mcq.correct_option_id } },
        { question_id: short_q.id, payload: { text: "blue" } },
        { question_id: open_q.id, payload: { text: "Because..." } },
        { question_id: ordering.id, payload: { order: ordering.correct_order_ids } },
        { question_id: matching.id, payload: { pairs: matching.pairs } }
      ]
    }, as: :json
    assert_response :success

    post student_submit_url(token: token), params: { attempt_id: attempt.id }
    follow_redirect!
    assert_response :success
    assert attempt.reload.submitted?
    assert_equal 1, attempt.answers.find_by!(question: mcq).auto_score.to_i
    assert_equal 2, attempt.answers.find_by!(question: ordering).auto_score.to_i
    assert_equal 3, attempt.answers.find_by!(question: matching).auto_score.to_i
  end
end
