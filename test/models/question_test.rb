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
    ordering_payload = QuestionSanitizer.for_student(ordering, seed: seed)
    matching_payload = QuestionSanitizer.for_student(matching, seed: seed)
    source_payload = QuestionSanitizer.for_student(source)
    mcq_payload = QuestionSanitizer.for_student(mcq)

    assert_equal ordering.shuffled_items(seed).map { |item| item["id"] },
                 ordering_payload[:items].map { |item| item["id"] }
    assert_equal %w[e1 e2 e3].sort, ordering_payload[:items].map { |item| item["id"] }.sort
    ordering_payload[:items].each { |item| assert_equal %w[id text], item.keys.sort }

    refute matching_payload.key?(:pairs)
    assert_equal matching.student_facing_left, matching_payload[:left]
    assert_equal matching.shuffled_right_items(seed).map { |item| item["id"] },
                 matching_payload[:right].map { |item| item["id"] }

    assert_equal "A short passage.", source_payload[:source]
    assert_equal "Summarize", source_payload[:prompt]
    refute_includes source_payload.values, "secret rubric"

    assert_equal %w[a b], mcq_payload[:options].map { |opt| opt["id"] }
    mcq_payload[:options].each { |opt| refute opt.key?("is_correct") }
  end
end
