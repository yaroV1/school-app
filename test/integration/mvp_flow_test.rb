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
    post subject_exams_url(subject), params: {
      exam: { title: "Unit 1", max_attempts: 1, time_limit_sec: 300, show_results_to_students: "1" }
    }
    exam = Exam.order(:id).last

    post test_questions_url(exam), params: {
      question: {
        question_type: "mcq",
        prompt: "2+2?",
        points: 1,
        correct_index: "1",
        photo: fixture_file_upload("pixel.png", "image/png"),
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
    assert_match "History of Ukraine", response.body

    post student_start_url(token: token)
    follow_redirect!
    assert_response :success
    assert_match "History of Ukraine", response.body
    assert_select "img[alt=?]", I18n.t("exams.show.photo_alt")

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

    sign_in_as @teacher
    patch attempt_url(attempt), params: {
      answers: [
        { question_id: short_q.id, teacher_score: 1, teacher_comment: "Добре" },
        { question_id: open_q.id, teacher_score: 2 },
        { question_id: source.id, teacher_score: 2 }
      ],
      teacher_comment: "Роботу перевірено",
      finalize: "1"
    }
    assert_redirected_to attempt_url(attempt)
    assert attempt.grade.reload.finalized_by_teacher?
    sign_out

    get student_done_url(token: token)
    assert_response :success
    assert_select "#student_result"
    assert_match I18n.t("attempts.report.earned", score: "11", max: "11"), response.body
    assert_select "#correct_answer_question_#{mcq.id}", text: /4/
    assert_match "Добре", response.body
    assert_match "Роботу перевірено", response.body
    refute_match "Mentions capital", response.body
  end

  test "closing a test does not lock a student out of the attempt in progress" do
    exam = create_exam!(@teacher, title: "Unit 2", status: :published, time_limit_sec: 300)
    exam.questions.create!(question_type: :short_text, prompt: "Sky?", points: 1, position: 0, config: {})
    student = @teacher.students.create!(name: "Ira")
    assignment = exam.assignments.create!(student: student)
    token = assignment.access_token

    post student_start_url(token: token)
    attempt = assignment.attempts.last
    exam.close!

    get student_portal_url(token: token)
    assert_response :success
    assert_match I18n.t("take.resume"), response.body

    post student_start_url(token: token)
    assert_redirected_to student_run_url(token: token)

    post student_submit_url(token: token), params: { attempt_id: attempt.id }
    assert_redirected_to student_done_url(token: token)
    assert attempt.reload.submitted?
  end

  test "student run page autosaves every 5 seconds and shows save status icons" do
    exam = create_exam!(@teacher, title: "Autosave", status: :published)
    exam.questions.create!(question_type: :short_text, prompt: "Sky?", points: 1, position: 0, config: {})
    student = @teacher.students.create!(name: "Nia")
    assignment = exam.assignments.create!(student: student)

    post student_start_url(token: assignment.access_token)
    follow_redirect!
    assert_response :success

    assert_select "form[data-autosave-interval-value=?]", "5000"
    assert_select "[data-autosave-target=?]", "status"
    assert_select "[data-autosave-target=?]", "check"
    assert_select "[data-autosave-target=?]", "spinner"
  end

  test "the submit control stays below the sticky bar, not inside it" do
    exam = create_exam!(@teacher, title: "Sticky", status: :published, time_limit_sec: 300)
    exam.questions.create!(question_type: :short_text, prompt: "Sky?", points: 1, position: 0, config: {})
    student = @teacher.students.create!(name: "Olia")
    assignment = exam.assignments.create!(student: student)

    post student_start_url(token: assignment.access_token)
    follow_redirect!
    assert_response :success

    # The clock and the save state ride along while scrolling; submitting ends
    # the attempt for good, so that button must not sit under a reader's thumb.
    assert_select ".run-bar [data-countdown-target=display]"
    assert_select ".run-bar [data-autosave-target=status]"
    assert_select ".run-bar input[type=submit]", false
    assert_select "form input[type=submit][value=?]", I18n.t("take.submit")
  end

  test "class tabs split subjects and students; subject tabs split tests and stats" do
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
    assert_match "World History", response.body
    assert_no_match(/Ann/, response.body)

    get students_class_group_url(group)
    assert_response :success
    assert_match "Ann", response.body

    get subject_url(subject)
    assert_response :success
    assert_match "Quiz", response.body
    assert_no_match(/Ann/, response.body)

    get stats_subject_url(subject)
    assert_response :success
    assert_match "Ann", response.body

    delete subject_url(subject)
    assert_redirected_to subject_url(subject)
    assert Subject.exists?(subject.id)

    delete class_group_url(group)
    assert_redirected_to class_group_url(group)
    assert ClassGroup.exists?(group.id)
  end
end
