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

  test "duplicate! copies settings and questions into a fresh draft with a cleared window" do
    exam = create_exam!(users(:one),
      title: "Атлантида", status: :closed, description: "Про міф", time_limit_sec: 600,
      max_attempts: 2, show_results_to_students: true,
      available_from: 2.days.ago, available_until: 1.day.ago)
    exam.questions.create!(question_type: :mcq, prompt: "Так чи ні?", points: 2, position: 0,
      config: { "options" => [
        { "id" => "a", "text" => "Так", "is_correct" => true },
        { "id" => "b", "text" => "Ні", "is_correct" => false }
      ] })
    exam.questions.create!(question_type: :short_text, prompt: "Опишіть", points: 1, position: 1, config: {})

    copy = exam.duplicate!

    assert copy.persisted?
    assert copy.draft?
    assert_equal exam.subject, copy.subject
    assert_equal exam.teacher, copy.teacher
    assert_equal I18n.t("exams.duplicate.copy_title", title: "Атлантида"), copy.title
    assert_equal "Про міф", copy.description
    assert_equal 600, copy.time_limit_sec
    assert_equal 2, copy.max_attempts
    assert copy.show_results_to_students
    assert_nil copy.available_from, "a copied window would open the copy already closed"
    assert_nil copy.available_until

    original, copied = exam.questions.to_a, copy.questions.to_a
    assert_equal original.map(&:prompt), copied.map(&:prompt)
    assert_equal original.map(&:config), copied.map(&:config)
    assert_equal original.map(&:points), copied.map(&:points)
    assert_equal original.map(&:position), copied.map(&:position)
    assert_empty original.map(&:id) & copied.map(&:id)
  end

  test "duplicate! copies the photo into a new blob so the copy outlives the original" do
    exam = create_exam!(users(:one))
    question = exam.questions.create!(question_type: :short_text, prompt: "Що на фото?", points: 1,
      position: 0, config: {})
    question.photo.attach(io: File.open(file_fixture("pixel.png")), filename: "pixel.png", content_type: "image/png")

    copied_photo = exam.duplicate!.questions.sole.photo

    assert copied_photo.attached?
    assert_not_equal question.photo.blob.id, copied_photo.blob.id, "a shared blob dies with the original question"
    assert_equal question.photo.download, copied_photo.download
    assert_equal "image/png", copied_photo.content_type
    assert_equal "pixel.png", copied_photo.filename.to_s
  end

  test "an unassigned exam moves to another class's subject, whatever its status" do
    teacher = users(:one)
    exam = create_exam!(teacher, status: :closed)
    target = teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")

    assert exam.update(subject: target), exam.errors.full_messages.to_sentence
    assert_equal target, exam.reload.subject
    assert_equal "8-Б", exam.class_group.name
    assert_equal teacher, exam.teacher
  end

  test "one assignment, even revoked, pins the exam to its subject" do
    teacher = users(:one)
    exam = create_exam!(teacher)
    exam.assignments.create!(student: teacher.students.create!(name: "Оля")).revoke!
    original = exam.subject
    target = teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")

    assert_not exam.update(subject: target)
    assert_includes exam.errors[:subject],
      I18n.t("activerecord.errors.models.exam.attributes.subject.has_assignments")
    assert_equal original, exam.reload.subject
  end

  test "duplicate! leaves assignments behind" do
    teacher = users(:one)
    exam = create_exam!(teacher, status: :published)
    exam.questions.create!(question_type: :short_text, prompt: "A", points: 1, position: 0, config: {})
    exam.assignments.create!(student: teacher.students.create!(name: "Оля"))

    copy = exam.duplicate!

    assert_empty copy.assignments
    assert_equal 1, exam.assignments.count
  end
end
