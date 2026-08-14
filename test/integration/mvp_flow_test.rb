require "test_helper"

class MvpFlowTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
  end

  test "teacher assigns links and student submits mcq short and open" do
    sign_in_as @teacher

    post class_groups_url, params: { class_group: { name: "10-A" } }
    group = ClassGroup.order(:id).last
    post class_group_students_url(group), params: { student: { name: "Sam" } }
    student = Student.order(:id).last

    post class_group_subjects_url(group), params: { subject: { name: "History of Ukraine" } }
    subject = Subject.order(:id).last
    post subject_exams_url(subject), params: { exam: { title: "Unit 1", max_attempts: 1, time_limit_sec: 300 } }
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

    post test_questions_url(exam), params: {
      question: {
        question_type: "source",
        prompt: "Summarize the passage",
        points: 2,
        source: "Kyiv is the capital of Ukraine.",
        rubric: "Mentions capital"
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
    mcq, short_q, open_q, ordering, matching, source = exam.questions.order(:position)

    put student_answers_url(token: token), params: {
      attempt_id: attempt.id,
      answers: [
        { question_id: mcq.id, payload: { option_id: mcq.correct_option_id } },
        { question_id: short_q.id, payload: { text: "blue" } },
        { question_id: open_q.id, payload: { text: "Because..." } },
        { question_id: ordering.id, payload: { order: ordering.correct_order_ids } },
        { question_id: matching.id, payload: { pairs: matching.pairs } },
        { question_id: source.id, payload: { text: "Kyiv is the capital." } }
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
    assert_equal "Kyiv is the capital.", attempt.answers.find_by!(question: source).text_response
    assert_nil attempt.answers.find_by!(question: source).auto_score
  end

  test "class page lists students and subjects; subject page lists tests and student stats" do
    sign_in_as @teacher

    post class_groups_url, params: { class_group: { name: "9-B" } }
    group = ClassGroup.order(:id).last
    post class_group_students_url(group), params: { student: { name: "Ann" } }
    post class_group_subjects_url(group), params: { subject: { name: "World History" } }
    subject = Subject.order(:id).last
    post subject_exams_url(subject), params: { exam: { title: "Quiz", max_attempts: 1 } }
    exam = Exam.order(:id).last
    assert_equal subject.id, exam.subject_id
    assert_equal group.id, exam.class_group.id

    get class_group_url(group)
    assert_response :success
    assert_match "Ann", response.body
    assert_match "World History", response.body

    get subject_url(subject)
    assert_response :success
    assert_match "Quiz", response.body
    assert_match "Ann", response.body

    delete subject_url(subject)
    assert_redirected_to subject_url(subject)
    assert Subject.exists?(subject.id)

    delete class_group_url(group)
    assert_redirected_to class_group_url(group)
    assert ClassGroup.exists?(group.id)
  end
end
