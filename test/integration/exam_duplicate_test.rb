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
      assert_select "a[href=?]", duplicate_test_path(@exam), 1,
                    "a #{status} test must offer duplication"
    end
  end

  test "duplicating a closed test lands on a fresh draft copy" do
    assert_difference [ "Exam.count", "Question.count" ], 1 do
      post duplicate_test_path(@exam), params: { subject_ids: [ @exam.subject_id.to_s ] }
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

  test "the duplicate page checkboxes the teacher's subjects by class, with the current one marked" do
    target = @teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")

    get duplicate_test_path(@exam)
    assert_response :success
    assert_select "form[action=?]", duplicate_test_path(@exam) do
      assert_select "p", text: "8-Б"
      assert_select "input[type=checkbox][name=?][value=?]", "subject_ids[]", target.id.to_s
      assert_select "input[type=checkbox][name=?][value=?][checked]",
        "subject_ids[]", @exam.subject_id.to_s, true,
        "the test's own subject starts selected, so duplicating in place stays one tap"
      assert_select "label", text: /#{I18n.t("exams.duplicate.current")}/
      assert_select "a[href=?]", test_path(@exam), text: I18n.t("exams.duplicate.cancel")
    end
    assert_select "dialog", false, "the picker is a page, not a dialog no old phone can open"
  end

  test "a foreign test has no duplicate page" do
    get duplicate_test_path(create_exam!(users(:two)))
    assert_response :not_found
  end

  test "the copy lands in the chosen subject" do
    target = @teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")

    post duplicate_test_path(@exam), params: { subject_ids: [ target.id.to_s ] }

    copy = Exam.order(:id).last
    assert_redirected_to test_path(copy)
    assert_equal target, copy.subject
    assert_equal [ "Q?" ], copy.questions.map(&:prompt)
    get subject_path(target)
    assert_select "a[href=?]", test_path(copy)
  end

  test "several subjects each get a copy and the teacher stays on the original" do
    history = @teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")
    geography = @exam.class_group.subjects.create!(name: "Географія")

    assert_difference "Exam.count", 3 do
      post duplicate_test_path(@exam),
        params: { subject_ids: [ @exam.subject_id.to_s, history.id.to_s, geography.id.to_s ] }
    end

    assert_redirected_to test_path(@exam)
    assert_equal I18n.t("exams.flash.duplicated_many", count: 3), flash[:notice]
    copies = Exam.where.not(id: @exam.id).order(:id)
    assert_equal [ @exam.subject, history, geography ].sort_by(&:id), copies.map(&:subject).sort_by(&:id)
    assert copies.all?(&:draft?)
    assert_equal [ [ "Q?" ] ], copies.map { |copy| copy.questions.map(&:prompt) }.uniq
  end

  test "the same subject twice still yields one copy" do
    assert_difference "Exam.count", 1 do
      post duplicate_test_path(@exam),
        params: { subject_ids: [ @exam.subject_id.to_s, @exam.subject_id.to_s ] }
    end
    assert_redirected_to test_path(Exam.order(:id).last)
  end

  test "an empty selection creates nothing and comes back to the picker" do
    assert_no_difference "Exam.count" do
      post duplicate_test_path(@exam), params: { subject_ids: [ "" ] }
    end
    assert_redirected_to duplicate_test_path(@exam)
    assert_equal I18n.t("exams.flash.duplicate_no_target"), flash[:alert]
  end

  test "a foreign target subject is a 404 and no copy is made" do
    foreign = users(:two).class_groups.create!(name: "9-В").subjects.create!(name: "Хімія")

    assert_no_difference "Exam.count" do
      post duplicate_test_path(@exam), params: { subject_ids: [ foreign.id.to_s ] }
      assert_response :not_found
    end
  end

  test "one foreign id among the teacher's own cancels the whole batch" do
    foreign = users(:two).class_groups.create!(name: "9-В").subjects.create!(name: "Хімія")

    assert_no_difference "Exam.count" do
      post duplicate_test_path(@exam),
        params: { subject_ids: [ @exam.subject_id.to_s, foreign.id.to_s ] }
      assert_response :not_found
    end
  end

  test "targets that are not an array of ids are ignored" do
    other = @teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")

    assert_no_difference "Exam.count" do
      post duplicate_test_path(@exam), params: { subject_ids: other.id.to_s }
      assert_redirected_to duplicate_test_path(@exam)

      post duplicate_test_path(@exam), params: { subject_ids: [ { id: other.id } ] }
      assert_redirected_to duplicate_test_path(@exam)
    end
    assert_equal I18n.t("exams.flash.duplicate_no_target"), flash[:alert]
  end

  test "a test with drifted question data fails with an alert, not a 500" do
    other = @teacher.class_groups.create!(name: "8-Б").subjects.create!(name: "Історія")
    @exam.questions.sole.update_column(:question_type, Question.question_types[:mcq])

    assert_no_difference "Exam.count" do
      post duplicate_test_path(@exam), params: { subject_ids: [ @exam.subject_id.to_s, other.id.to_s ] }
    end
    assert_redirected_to test_path(@exam)
    assert_equal I18n.t("exams.flash.duplicate_failed"), flash[:alert]
  end

  test "a foreign test cannot be duplicated" do
    other = create_exam!(users(:two))

    assert_no_difference "Exam.count" do
      post duplicate_test_path(other), params: { subject_ids: [ @exam.subject_id.to_s ] }
      assert_response :not_found
    end
  end
end
