require "test_helper"

# A list row is opened by clicking the row. The title carries the only link and a CSS
# overlay stretches its hit area, so what these guard against is a second link back to the
# same record — the "Відкрити" button that used to sit at the end of every row. It was
# redundant to click and a second tab stop to somewhere the keyboard had already been.
class ListRowNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @group = @teacher.class_groups.create!(name: "10-A")
    @subject = @group.subjects.create!(name: "Алгебра")
    @exam = create_exam!(@teacher, title: "Розділ 1", subject: @subject)
    @student = @teacher.students.create!(name: "Ada Lovelace")
    @group.add_student!(@student)
  end

  # The home page is the one card grid; a card follows the same rule as a row.
  test "a class card opens the class and offers no second way in" do
    get class_groups_path

    assert_response :success
    assert_select ".tablet-card a[href=?]", class_group_path(@group), 1,
                  "the card should link to the class exactly once"
    assert_select "a.tablet-card-title[href=?]", class_group_path(@group), 1,
                  "and that one link should be the title"
    assert_select "a.tablet-card-new[href=?]", new_class_group_path, 1,
                  "creation lives on the shelf as the dashed card"
  end

  test "a subject row opens the subject and offers no second way in" do
    get class_group_path(@group)

    assert_row_opens_once subject_path(@subject)
    assert_select ".card", false
  end

  test "a test row opens the test and offers no second way in" do
    get subject_path(@subject)

    assert_row_opens_once test_path(@exam)
  end

  test "a student row keeps the actions that are not the row's destination" do
    get students_class_group_path(@group)

    assert_row_opens_once student_path(@student)
    # Edit and remove go somewhere else, so they stay — and they have to sit in the
    # container that lifts them above the overlay, or the row would swallow their clicks.
    assert_select ".list-row .list-row-actions a[href=?]", edit_student_path(@student)
    assert_select ".list-row .list-row-actions form[action=?]",
                  remove_member_class_group_path(@group, student_id: @student.id)
    assert_select ".card", false
  end

  private

  def assert_row_opens_once(path)
    assert_response :success
    assert_select ".list-row a[href=?]", path, 1, "the row should link to the record exactly once"
    assert_select "a.list-row-title[href=?]", path, 1, "and that one link should be the title"
  end
end
