require "test_helper"

class SubjectTestsFilterTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
    sign_in_as @teacher
    @group = @teacher.class_groups.create!(name: "10-A")
    @subject = @group.subjects.create!(name: "Історія")

    @algebra = create_exam!(@teacher, subject: @subject, title: "Алгебра", created_at: 3.days.ago)
    @biology = create_exam!(@teacher, subject: @subject, title: "Біологія", created_at: 2.days.ago)
    @geometry = create_exam!(@teacher, subject: @subject, title: "Геометрія", created_at: 1.day.ago)
  end

  test "search matches a Cyrillic title regardless of case" do
    get subject_path(@subject), params: { q: "алгебра" }
    assert_response :success
    assert_equal [ "Алгебра" ], listed_titles

    get subject_path(@subject), params: { q: "АЛГЕБРА" }
    assert_response :success
    assert_equal [ "Алгебра" ], listed_titles
  end

  test "search matches on a substring and reports when nothing is found" do
    get subject_path(@subject), params: { q: "гебр" }
    assert_response :success
    assert_equal [ "Алгебра" ], listed_titles

    get subject_path(@subject), params: { q: "хімія" }
    assert_response :success
    assert_empty listed_titles
    assert_match I18n.t("subjects.show.no_matches", query: "хімія"), response.body
    assert_select ".empty-state .empty-state-illustration svg[aria-hidden=true]"
  end

  test "defaults to newest created first" do
    get subject_path(@subject)
    assert_response :success
    assert_equal [ "Геометрія", "Біологія", "Алгебра" ], listed_titles
  end

  test "sorts by creation date and by title" do
    get subject_path(@subject), params: { sort: "created_asc" }
    assert_equal [ "Алгебра", "Біологія", "Геометрія" ], listed_titles

    get subject_path(@subject), params: { sort: "created_desc" }
    assert_equal [ "Геометрія", "Біологія", "Алгебра" ], listed_titles

    # Lowercase sorts among the others, not after them the way SQLite's byte
    # order would put it.
    @geometry.update!(title: "антресоль")
    get subject_path(@subject), params: { sort: "title" }
    assert_equal [ "Алгебра", "антресоль", "Біологія" ], listed_titles
  end

  test "an unknown sort falls back to the default instead of raising" do
    get subject_path(@subject), params: { sort: "title; drop table exams" }
    assert_response :success
    assert_equal [ "Геометрія", "Біологія", "Алгебра" ], listed_titles
  end

  test "search and sort combine and survive in the url" do
    get subject_path(@subject), params: { q: "і", sort: "created_asc" }
    assert_response :success
    assert_equal [ "Біологія", "Геометрія" ], listed_titles
  end

  private

  def listed_titles
    css_select("section ul li a.list-row-title").map(&:text).map(&:strip)
  end
end
