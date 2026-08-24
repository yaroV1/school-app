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
    assert_select "select[name='exam[subject_id]'] option[selected][value=?]", @source.id.to_s

    get new_subject_exam_path(@source)
    assert_select "select[name='exam[subject_id]']", false, "a new test is created from its subject page"
  end

  test "moving an unassigned test relocates it, within its class or to another" do
    sibling = @source.class_group.subjects.create!(name: "Історія культури")
    patch test_path(@exam), params: { exam: { subject_id: sibling.id } }
    assert_equal sibling, @exam.reload.subject

    patch test_path(@exam), params: { exam: { subject_id: @target.id } }
    assert_redirected_to test_path(@exam)
    assert_equal I18n.t("exams.flash.updated"), flash[:notice]
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
    # The refused target must not leak into the re-rendered page: hint and breadcrumbs
    # keep naming the subject the exam actually belongs to.
    assert_select "p.field-hint",
      text: I18n.t("exams.form.subject_locked", subject: "10-А — Всесвітня історія")
    assert_select "a[href=?]", subject_path(@source)
  end

  test "an array-shaped subject_id is ignored, not a 500" do
    patch test_path(@exam), params: { exam: { subject_id: [ @target.id ] } }
    assert_redirected_to test_path(@exam)
    assert_equal @source, @exam.reload.subject
  end

  test "another teacher's subject cannot be the target" do
    foreign = users(:two).class_groups.create!(name: "9-В").subjects.create!(name: "Хімія")

    patch test_path(@exam), params: { exam: { subject_id: foreign.id } }
    assert_response :not_found
    assert_equal @source, @exam.reload.subject
  end
end
