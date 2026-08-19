require "test_helper"
require "csv"

class GradesExportTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @group = @teacher.class_groups.create!(name: "10-A")
    @exam = create_exam!(@teacher, title: "Quiz", max_attempts: 2, status: :published, class_group: @group)
  end

  test "owner downloads results csv with bom semicolon rows ordered by name" do
    now = Time.zone.parse("2026-03-15 12:00")
    zed = assign_student!("Zed")
    ann = assign_student!("Ann")
    semicolon = assign_student!("Ada; Lovelace")
    assign_student!("No Attempt")

    zed_first = started_attempt!(zed, attempt_no: 1, status: :submitted, at: now, submitted_at: now)
    zed_first.create_grade!(max_score: 5, total_score: 1)
    zed_latest = started_attempt!(zed, attempt_no: 2, status: :submitted, at: now + 1.hour, submitted_at: now + 1.hour)
    zed_grade = zed_latest.create_grade!(max_score: 5, total_score: 3.5)

    started_attempt!(ann, attempt_no: 1, status: :in_progress, at: now)
    started_attempt!(semicolon, attempt_no: 1, status: :expired, at: now)

    get results_test_path(@exam)
    assert_response :success

    get results_test_path(@exam, format: :csv)
    assert_response :success
    assert_match %r{text/csv}, response.media_type

    rows = parse_journal_csv(response.body)
    assert_equal [
      I18n.t("exams.assign.student"),
      I18n.t("exams.results.latest_status"),
      I18n.t("attempts.history.started"),
      I18n.t("exams.results.submitted"),
      I18n.t("exams.results.score"),
      I18n.t("exams.results.max_score")
    ], rows.first
    assert_equal 5, rows.size

    names = rows.drop(1).map(&:first)
    assert_equal [ "Ada; Lovelace", "Ann", "No Attempt", "Zed" ], names

    ada_row = rows[1]
    assert_equal 6, ada_row.size
    assert_equal I18n.t("statuses.expired"), ada_row[1]
    assert_equal "", ada_row[4]
    assert_equal "", ada_row[5]

    ann_row = rows[2]
    assert_equal I18n.t("statuses.in_progress"), ann_row[1]
    assert_equal I18n.l(now, format: :short), ann_row[2]
    assert_equal "", ann_row[3]
    assert_equal "", ann_row[4]
    assert_equal "", ann_row[5]

    empty_row = rows[3]
    assert_equal I18n.t("statuses.not_started"), empty_row[1]
    assert_equal [ "", "", "", "" ], empty_row[2..]

    zed_row = rows[4]
    assert_equal I18n.t("statuses.submitted"), zed_row[1]
    assert_equal I18n.l(zed_latest.started_at, format: :short), zed_row[2]
    assert_equal I18n.l(zed_latest.submitted_at, format: :short), zed_row[3]
    assert_equal zed_grade.total_score.to_d.to_s("F"), zed_row[4]
    assert_equal zed_grade.max_score.to_d.to_s("F"), zed_row[5]
  end

  test "results csv is headers only when the test has no assignments" do
    get results_test_path(@exam, format: :csv)
    assert_response :success
    rows = parse_journal_csv(response.body)
    assert_equal 1, rows.size
    assert_equal I18n.t("exams.assign.student"), rows.first.first
  end

  test "owner downloads stats csv matching student_stat_rows" do
    now = Time.zone.parse("2026-03-15 12:00")
    scored = assign_student!("Ann")
    idle = @teacher.students.create!(name: "Bea")
    @group.add_student!(idle)

    attempt = started_attempt!(scored, attempt_no: 1, status: :submitted, at: now, submitted_at: now)
    attempt.create_grade!(max_score: 4, total_score: 3)

    get stats_subject_path(@exam.subject)
    assert_response :success

    get stats_subject_path(@exam.subject, format: :csv)
    assert_response :success
    assert_match %r{text/csv}, response.media_type

    rows = parse_journal_csv(response.body)
    expected = @exam.subject.student_stat_rows
    assert_equal [
      I18n.t("subjects.stats.student"),
      I18n.t("subjects.stats.tests"),
      I18n.t("subjects.stats.average"),
      I18n.t("subjects.stats.last")
    ], rows.first
    assert_equal expected.size + 1, rows.size

    expected.each_with_index do |stat, index|
      row = rows[index + 1]
      assert_equal stat.student.name, row[0]
      progress = if stat.assigned.positive?
        I18n.t("subjects.stats.progress", finished: stat.finished, assigned: stat.assigned)
      else
        ""
      end
      assert_equal progress, row[1]
      assert_equal stat.average_percent.nil? ? "" : stat.average_percent.to_s, row[2]
      assert_equal stat.last_activity_at ? I18n.l(stat.last_activity_at, format: :short) : "", row[3]
    end
  end

  test "another teacher cannot download either csv" do
    sign_in_as users(:two)

    get results_test_path(@exam, format: :csv)
    assert_response :not_found

    get stats_subject_path(@exam.subject, format: :csv)
    assert_response :not_found
  end

  test "signed-out request for either csv redirects to sign-in" do
    sign_out

    get results_test_path(@exam, format: :csv)
    assert_redirected_to new_session_path

    get stats_subject_path(@exam.subject, format: :csv)
    assert_redirected_to new_session_path
  end

  private

  def assign_student!(name)
    student = @teacher.students.create!(name: name)
    @group.add_student!(student)
    @exam.assignments.create!(student: student)
  end

  def started_attempt!(assignment, attempt_no:, status:, at:, submitted_at: nil)
    assignment.attempts.create!(
      attempt_no: attempt_no,
      status: status,
      started_at: at,
      last_activity_at: at,
      submitted_at: submitted_at
    )
  end

  def parse_journal_csv(body)
    assert_equal "\uFEFF", body[0]
    CSV.parse(body.delete_prefix("\uFEFF"), col_sep: ";")
  end
end
