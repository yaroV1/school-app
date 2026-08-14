require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  setup do
    @exam = users(:one).exams.create!(title: "Quiz", max_attempts: 1)
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

  test "sanitizer omits correct order and pairs" do
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

    ordering_payload = QuestionSanitizer.for_student(ordering)
    matching_payload = QuestionSanitizer.for_student(matching)

    assert_equal %w[e1 e2 e3], ordering_payload[:items].map { |item| item["id"] }
    assert_nil ordering_payload[:options]
    refute matching_payload.key?(:pairs)
    assert_equal %w[l1 l2], matching_payload[:left].map { |item| item["id"] }
    assert_equal %w[r1 r2], matching_payload[:right].map { |item| item["id"] }
  end
end
