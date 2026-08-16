require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  setup do
    @exam = create_exam!(users(:one), title: "Quiz")
  end

  test "ordering requires at least three items" do
    question = @exam.questions.new(
      question_type: :ordering,
      prompt: "Order",
      points: 1,
      position: 0,
      config: { "items" => [ { "id" => "e1", "text" => "One" }, { "id" => "e2", "text" => "Two" } ] }
    )
    assert_not question.valid?
    assert_includes question.errors[:config], I18n.t("activerecord.errors.models.question.attributes.config.too_few_items")
  end

  test "matching requires at least two pairs" do
    question = @exam.questions.new(
      question_type: :matching,
      prompt: "Match",
      points: 1,
      position: 0,
      config: {
        "left" => [ { "id" => "l1", "text" => "A" } ],
        "right" => [ { "id" => "r1", "text" => "1" } ],
        "pairs" => { "l1" => "r1" }
      }
    )
    assert_not question.valid?
  end

  test "source requires pasted text" do
    question = @exam.questions.new(
      question_type: :source,
      prompt: "Summarize",
      points: 1,
      position: 0,
      config: { "source" => "  " }
    )
    assert_not question.valid?
    assert_includes question.errors[:config], I18n.t("activerecord.errors.models.question.attributes.config.blank_source")
  end

  test "sanitizer strips answer keys and shuffles order-sensitive lists" do
    ordering = @exam.questions.create!(
      question_type: :ordering,
      prompt: "Order",
      points: 1,
      position: 0,
      config: {
        "items" => [
          { "id" => "e1", "text" => "First" },
          { "id" => "e2", "text" => "Second" },
          { "id" => "e3", "text" => "Third" }
        ]
      }
    )
    matching = @exam.questions.create!(
      question_type: :matching,
      prompt: "Match",
      points: 1,
      position: 1,
      config: {
        "left" => [ { "id" => "l1", "text" => "A" }, { "id" => "l2", "text" => "B" } ],
        "right" => [ { "id" => "r1", "text" => "1" }, { "id" => "r2", "text" => "2" } ],
        "pairs" => { "l1" => "r1", "l2" => "r2" }
      }
    )
    source = @exam.questions.create!(
      question_type: :source,
      prompt: "Summarize",
      points: 2,
      position: 2,
      config: { "source" => "A short passage.", "rubric" => "secret rubric" }
    )
    mcq = @exam.questions.create!(
      question_type: :mcq,
      prompt: "Pick",
      points: 1,
      position: 3,
      config: {
        "options" => [
          { "id" => "a", "text" => "No", "is_correct" => false },
          { "id" => "b", "text" => "Yes", "is_correct" => true }
        ]
      }
    )

    seed = 42

    # Ordering: every item reaches the student, shuffled, carrying nothing but id and text.
    ordering_items = ordering.shuffled_items(seed)
    assert_equal %w[e1 e2 e3].sort, ordering_items.map { |item| item["id"] }.sort
    ordering_items.each { |item| assert_equal %w[id text], item.keys.sort }

    # Matching: left as stored, right shuffled, the pairs answer key never in either.
    assert_equal %w[l1 l2], matching.student_facing_left.map { |item| item["id"] }
    assert_equal %w[r1 r2].sort, matching.shuffled_right_items(seed).map { |item| item["id"] }.sort
    (matching.student_facing_left + matching.shuffled_right_items(seed)).each do |item|
      assert_equal %w[id text], item.keys.sort
    end

    # Source: the passage is student-visible, the rubric shares its config hash and is not.
    assert_equal "A short passage.", source.source_text
    assert_equal "secret rubric", source.rubric, "fixture must keep a rubric for this to prove anything"

    # MCQ: options without the correct flag.
    assert_equal %w[a b], mcq.student_facing_options.map { |opt| opt["id"] }
    mcq.student_facing_options.each { |opt| assert_equal %w[id text], opt.keys.sort }
  end

  test "photo is optional" do
    question = @exam.questions.new(
      question_type: :short_text,
      prompt: "Look",
      points: 1,
      position: 0,
      config: {}
    )
    assert question.valid?
  end

  test "photo must be an image" do
    question = @exam.questions.new(
      question_type: :short_text,
      prompt: "Look",
      points: 1,
      position: 0,
      config: {}
    )
    question.photo.attach(
      io: StringIO.new("not an image"),
      filename: "notes.txt",
      content_type: "text/plain"
    )
    assert_not question.valid?
    assert_includes question.errors[:photo], I18n.t("activerecord.errors.models.question.attributes.photo.invalid_type")
  end
end
