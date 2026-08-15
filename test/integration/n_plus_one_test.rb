require "test_helper"

class NPlusOneTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @group = @teacher.class_groups.create!(name: "10-A")
    @exam = create_exam!(@teacher, title: "Quiz", max_attempts: 2, status: :published, class_group: @group)
    @exam.questions.create!(question_type: :short_text, prompt: "Name?", points: 1, position: 0, config: {})
  end

  test "results page does not query attempts or grades per assignment" do
    seed_assignments! 8, attempts: 1
    get results_test_path(@exam)
    assert_response :success

    sql = capture_sql { get results_test_path(@exam) }
    assert_no_per_record_loads sql, "attempts", "assignment_id"
    assert_no_per_record_loads sql, "grades", "attempt_id"
  end

  test "results page lists each assignment once when students have several attempts" do
    seed_assignments! 3, attempts: 2
    get results_test_path(@exam)
    assert_response :success
    assert_select "tbody tr", 3
  end

  test "manage page does not count attempts per assignment" do
    seed_assignments! 8, attempts: 1
    get manage_test_assignments_path(@exam)
    assert_response :success

    sql = capture_sql { get manage_test_assignments_path(@exam) }
    assert_no_per_record_loads sql, "attempts", "assignment_id"
    refute sql.any? { |query| query.match?(/SELECT COUNT\(\*\).*FROM "attempts"/i) }, sql.join("\n")
  end

  test "manage page lists each assignment once when students have several attempts" do
    seed_assignments! 3, attempts: 2
    get manage_test_assignments_path(@exam)
    assert_response :success
    assert_select "tbody tr", 3
  end

  test "live board does not query attempts per assignment" do
    seed_assignments! 8, attempts: 1
    headers = { "Turbo-Frame" => "live_board" }
    get live_test_path(@exam), headers: headers
    assert_response :success

    sql = capture_sql { get live_test_path(@exam), headers: headers }
    assert_no_per_record_loads sql, "attempts", "assignment_id"
    assert_no_per_record_loads sql, "students", "id"
  end

  test "live board lists each assignment once when students have several attempts" do
    seed_assignments! 3, attempts: 2
    get live_test_path(@exam), headers: { "Turbo-Frame" => "live_board" }
    assert_response :success
    assert_select "tbody tr", 3
  end

  test "class index does not query students or subjects per class" do
    6.times do |i|
      group = @teacher.class_groups.create!(name: "Class #{i}")
      student = @teacher.students.create!(name: "Student #{i}")
      group.add_student!(student)
      group.subjects.create!(name: "Subject #{i}")
    end

    get class_groups_path
    assert_response :success
    sql = capture_sql { get class_groups_path }
    assert_no_per_record_loads sql, "class_memberships", "class_group_id"
    assert_no_per_record_loads sql, "subjects", "class_group_id"
  end

  test "subject stats do not query assignments per exam or attempts per assignment" do
    seed_assignments! 8, attempts: 1
    get subject_path(@exam.subject)
    assert_response :success

    sql = capture_sql { get subject_path(@exam.subject) }
    assert_no_per_record_loads sql, "assignments", "exam_id"
    assert_no_per_record_loads sql, "attempts", "assignment_id"
    assert_no_per_record_loads sql, "grades", "attempt_id"
  end

  test "student history does not load the exam per attempt" do
    student = @teacher.students.create!(name: "Historian")
    @group.add_student!(student)
    now = Time.current
    3.times do |i|
      exam = create_exam!(@teacher, title: "Quiz #{i}", status: :published, class_group: @group)
      assignment = exam.assignments.create!(student: student)
      assignment.attempts.create!(
        attempt_no: 1,
        status: :submitted,
        started_at: now,
        last_activity_at: now,
        submitted_at: now
      )
    end

    get student_path(student)
    assert_response :success

    sql = capture_sql { get student_path(student) }
    exam_loads = sql.select { |query| query.match?(/FROM "exams"/i) }
    assert_operator exam_loads.size, :<=, 1, exam_loads.join("\n")
  end

  test "student autosave does not preload all attempts for the assignment" do
    student = @teacher.students.create!(name: "Sam")
    @group.add_student!(student)
    assignment = @exam.assignments.create!(student: student)
    now = Time.current
    attempt = assignment.attempts.create!(
      attempt_no: 1,
      status: :in_progress,
      started_at: now,
      last_activity_at: now
    )
    question = @exam.questions.first

    sql = capture_sql do
      put student_answers_url(token: assignment.access_token), params: {
        attempt_id: attempt.id,
        answers: [ { question_id: question.id, payload: { text: "Ada" } } ]
      }, as: :json
    end
    assert_response :success

    preloads = sql.select { |query| query.match?(/FROM "attempts"/i) && !query.match?(/"attempts"."id"/) }
    assert_empty preloads, preloads.join("\n")
  end

  private

  def seed_assignments!(count, attempts: 1)
    now = Time.current
    count.times do |i|
      student = @teacher.students.create!(name: "Student #{i} #{SecureRandom.hex(2)}")
      @group.add_student!(student)
      assignment = @exam.assignments.create!(student: student)
      attempts.times do |n|
        attempt = assignment.attempts.create!(
          attempt_no: n + 1,
          status: :submitted,
          started_at: now,
          last_activity_at: now,
          submitted_at: now
        )
        attempt.create_grade!(max_score: 1, total_score: 1)
      end
    end
  end

  def capture_sql
    ActiveRecord::Base.lease_connection.materialize_transactions
    # The query cache survives the warm-up request, and SQLCounter skips cache
    # hits, so without this every assertion below would see zero queries.
    ActiveRecord::Base.lease_connection.clear_query_cache
    counter = ActiveRecord::Assertions::QueryAssertions::SQLCounter.new
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    counter.log
  end

  def assert_no_per_record_loads(sql, table, fk)
    pattern = /FROM "#{table}".*WHERE "#{table}"."#{fk}" = /m
    matches = sql.select { |query| query.match?(pattern) }
    assert_operator matches.size, :<=, 1, "per-record #{table} queries (#{matches.size}):\n#{matches.join("\n")}"
  end
end
