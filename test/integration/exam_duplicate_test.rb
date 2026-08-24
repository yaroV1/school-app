require "test_helper"

class ExamDuplicateTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @exam = create_exam!(@teacher, title: "Контрольна", status: :closed)
    @exam.questions.create!(question_type: :short_text, prompt: "Q?", points: 1, position: 0, config: {})
  end

  test "the duplicate button is offered in every state" do
    %i[draft published closed].each do |status|
      @exam.update_column(:status, Exam.statuses[status])

      get test_path(@exam)
      assert_response :success
      assert_select "form[action=?]", duplicate_test_path(@exam), 1,
                    "a #{status} test must offer duplication"
    end
  end

  test "duplicating a closed test lands on a fresh draft copy" do
    assert_difference [ "Exam.count", "Question.count" ], 1 do
      post duplicate_test_path(@exam)
    end

    copy = Exam.order(:id).last
    assert_redirected_to test_path(copy)
    follow_redirect!
    assert_response :success

    assert copy.draft?
    assert_equal I18n.t("exams.duplicate.copy_title", title: "Контрольна"), copy.title
    assert_equal [ "Q?" ], copy.questions.map(&:prompt)
    assert_empty copy.assignments
  end

  test "the header select offers the teacher's subjects by class, current one selected" do
    @teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")

    get test_path(@exam)
    assert_select "form[action=?] select[name=?]", duplicate_test_path(@exam), "subject_id" do
      assert_select "optgroup[label=?]", "8-Б"
      assert_select "option[selected][value=?]", @exam.subject_id.to_s
    end
  end

  test "the copy lands in the chosen subject" do
    target = @teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")

    post duplicate_test_path(@exam), params: { subject_id: target.id.to_s }

    copy = Exam.order(:id).last
    assert_redirected_to test_path(copy)
    assert_equal target, copy.subject
    assert_equal [ "Q?" ], copy.questions.map(&:prompt)
    get subject_path(target)
    assert_select "a[href=?]", test_path(copy)
  end

  test "a foreign target subject is a 404 and no copy is made" do
    foreign = users(:two).class_groups.create!(name: "9-В").subjects.create!(name: "Хімія")

    assert_no_difference "Exam.count" do
      post duplicate_test_path(@exam), params: { subject_id: foreign.id.to_s }
      assert_response :not_found
    end
  end

  test "an array-shaped target is ignored and the copy stays in the exam's subject" do
    other = @teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")

    assert_difference "Exam.count", 1 do
      post duplicate_test_path(@exam), params: { subject_id: [ other.id ] }
    end
    assert_equal @exam.subject, Exam.order(:id).last.subject
  end

  test "a test with drifted question data fails with an alert, not a 500" do
    @exam.questions.sole.update_column(:question_type, Question.question_types[:mcq])

    assert_no_difference "Exam.count" do
      post duplicate_test_path(@exam)
    end
    assert_redirected_to test_path(@exam)
    assert_equal I18n.t("exams.flash.duplicate_failed"), flash[:alert]
  end

  test "a foreign test cannot be duplicated" do
    other = create_exam!(users(:two))

    assert_no_difference "Exam.count" do
      post duplicate_test_path(other)
      assert_response :not_found
    end
  end
end
