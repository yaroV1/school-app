require "test_helper"

class ExamMoveTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @source = @teacher.class_groups.create!(name: "10-А").subjects.create!(name: "Всесвітня історія")
    @target = @teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія України")
    @exam = create_exam!(@teacher, title: "Контрольна", subject: @source)
  end

  test "the settings form groups the teacher's subjects by class, only once the test exists" do
    get edit_test_path(@exam)
    assert_response :success
    assert_select "select[name='exam[subject_id]'] optgroup[label=?]", "8-Б" do
      assert_select "option", "Історія України"
    end

    get new_subject_exam_path(@source)
    assert_select "select[name='exam[subject_id]']", false, "a new test is created from its subject page"
  end

  test "moving an unassigned test relocates it to the other class's subject" do
    patch test_path(@exam), params: { exam: { subject_id: @target.id } }
    assert_redirected_to test_path(@exam)
    assert_equal @target, @exam.reload.subject

    get subject_path(@source)
    assert_select "a[href=?]", test_path(@exam), false, "the old subject page still lists the moved test"
    get subject_path(@target)
    assert_select "a[href=?]", test_path(@exam)
  end

  test "an assigned test hides the select and rejects the move" do
    @exam.assignments.create!(student: @teacher.students.create!(name: "Оля")).revoke!

    get edit_test_path(@exam)
    assert_select "select[name='exam[subject_id]']", false
    assert_select "p.field-hint",
      text: I18n.t("exams.form.subject_locked", subject: "10-А — Всесвітня історія")

    patch test_path(@exam), params: { exam: { subject_id: @target.id } }
    assert_response :unprocessable_entity
    assert_equal @source, @exam.reload.subject
  end

  test "another teacher's subject cannot be the target" do
    foreign = users(:two).class_groups.create!(name: "9-В").subjects.create!(name: "Хімія")

    patch test_path(@exam), params: { exam: { subject_id: foreign.id } }
    assert_response :not_found
    assert_equal @source, @exam.reload.subject
  end
end
