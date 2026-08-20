require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  MCQ_CONFIG = {
    "options" => [
      { "id" => "a", "text" => "No", "is_correct" => false },
      { "id" => "b", "text" => "Yes", "is_correct" => true }
    ]
  }.freeze
  ORDERING_CONFIG = {
    "items" => [
      { "id" => "e1", "text" => "First" },
      { "id" => "e2", "text" => "Second" },
      { "id" => "e3", "text" => "Third" }
    ]
  }.freeze
  MATCHING_CONFIG = {
    "left" => [ { "id" => "l1", "text" => "A" }, { "id" => "l2", "text" => "B" } ],
    "right" => [ { "id" => "r1", "text" => "1" }, { "id" => "r2", "text" => "2" } ],
    "pairs" => { "l1" => "r1", "l2" => "r2" }
  }.freeze
  SOURCE_CONFIG = {
    "source" => "A short passage.",
    "rubric" => "secret rubric",
    "model_answer" => "secret answer"
  }.freeze

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

  test "a published question accepts a wording-only change" do
    mcq = publish(question_with(:mcq, MCQ_CONFIG))
    reworded_options = { "options" => [
      { "id" => "a", "text" => "Ні", "is_correct" => false },
      { "id" => "b", "text" => "Так", "is_correct" => true }
    ] }
    assert mcq.update(prompt: "Оберіть правильну відповідь", config: reworded_options),
      mcq.errors.full_messages.to_sentence
    assert_equal %w[Ні Так], mcq.reload.config["options"].map { |option| option["text"] }
    assert_equal "Оберіть правильну відповідь", mcq.prompt

    matching = publish(question_with(:matching, MATCHING_CONFIG))
    reworded_pairs = MATCHING_CONFIG.deep_dup
    reworded_pairs["left"][0]["text"] = "Альфа"
    reworded_pairs["right"][1]["text"] = "Два"
    assert matching.update(config: reworded_pairs), matching.errors.full_messages.to_sentence
    assert_equal "Альфа", matching.reload.config["left"][0]["text"]

    source = publish(question_with(:source, SOURCE_CONFIG))
    assert source.update(config: SOURCE_CONFIG.merge("source" => "A corrected passage.")),
      source.errors.full_messages.to_sentence
    assert_equal "A corrected passage.", source.reload.source_text
  end

  test "a published question tracks a config mutated in place" do
    question = publish(question_with(:mcq, MCQ_CONFIG))

    question.config["options"][0]["text"] = "Ніколи"
    assert question.valid?, question.errors.full_messages.to_sentence

    question.reload.config["options"][0]["is_correct"] = true
    assert_structure_frozen question
  end

  test "a published question refuses a source key on a type that has none" do
    question = publish(question_with(:mcq, MCQ_CONFIG))

    question.config = MCQ_CONFIG.merge("source" => "injected")
    assert_structure_frozen question
  end

  test "a published question with a malformed entry is refused, not raised on" do
    malformed = { "items" => [
      "plain string",
      { "id" => "e2", "text" => "Second" },
      { "id" => "e3", "text" => "Third" }
    ] }
    question = publish(question_with(:ordering, malformed))

    question.prompt = "Reworded"
    assert question.valid?, question.errors.full_messages.to_sentence

    question.reload.config = malformed.deep_dup.tap { |config| config["items"][0] = "changed string" }
    assert_structure_frozen question
  end

  test "a published question refuses a points, type, or position change" do
    question = publish(question_with(:mcq, MCQ_CONFIG))

    assert_not question.update(points: 5), "a points change must not persist"
    assert_structure_frozen question
    assert_equal 1, question.reload.points

    question.question_type = :short_text
    assert_structure_frozen question

    question.reload.position = 3
    assert_structure_frozen question
  end

  test "a published question refuses a change to entry ids, correctness, or count" do
    question = publish(question_with(:mcq, MCQ_CONFIG))

    question.config = { "options" => [
      { "id" => "z", "text" => "No", "is_correct" => false },
      { "id" => "b", "text" => "Yes", "is_correct" => true }
    ] }
    assert_structure_frozen question

    question.reload.config = { "options" => [
      { "id" => "a", "text" => "No", "is_correct" => true },
      { "id" => "b", "text" => "Yes", "is_correct" => false }
    ] }
    assert_structure_frozen question

    question.reload.config = { "options" => [
      { "id" => "a", "text" => "No", "is_correct" => false },
      { "id" => "b", "text" => "Yes", "is_correct" => true },
      { "id" => "c", "text" => "Maybe", "is_correct" => false }
    ] }
    assert_structure_frozen question
  end

  test "a published question refuses a reordered list or a remapped pair" do
    ordering = publish(question_with(:ordering, ORDERING_CONFIG))
    ordering.config = { "items" => ORDERING_CONFIG["items"].reverse }
    assert_structure_frozen ordering

    matching = publish(question_with(:matching, MATCHING_CONFIG))
    matching.config = MATCHING_CONFIG.merge("pairs" => { "l1" => "r2", "l2" => "r1" })
    assert_structure_frozen matching
  end

  test "a published question refuses a rubric or model answer change" do
    question = publish(question_with(:source, SOURCE_CONFIG))

    question.config = SOURCE_CONFIG.merge("rubric" => "reworded rubric")
    assert_structure_frozen question

    question.reload.config = SOURCE_CONFIG.merge("model_answer" => "reworded answer")
    assert_structure_frozen question
  end

  test "a draft question accepts every change a published one refuses" do
    mcq = question_with(:mcq, MCQ_CONFIG)
    mcq.points = 5
    mcq.position = 3
    mcq.config = { "options" => [
      { "id" => "z", "text" => "No", "is_correct" => true },
      { "id" => "b", "text" => "Yes", "is_correct" => false },
      { "id" => "c", "text" => "Maybe", "is_correct" => false }
    ] }
    assert mcq.save, mcq.errors.full_messages.to_sentence

    ordering = question_with(:ordering, ORDERING_CONFIG)
    ordering.config = { "items" => ORDERING_CONFIG["items"].reverse }
    assert ordering.save, ordering.errors.full_messages.to_sentence

    matching = question_with(:matching, MATCHING_CONFIG)
    assert matching.update(config: MATCHING_CONFIG.merge("pairs" => { "l1" => "r2", "l2" => "r1" })),
      matching.errors.full_messages.to_sentence

    source = question_with(:source, SOURCE_CONFIG)
    reworded = SOURCE_CONFIG.merge("rubric" => "reworded rubric", "model_answer" => "reworded answer")
    assert source.update(config: reworded), source.errors.full_messages.to_sentence

    retyped = question_with(:mcq, MCQ_CONFIG)
    assert retyped.update(question_type: :short_text), retyped.errors.full_messages.to_sentence
  end

  # FR-8. The shared MATCHING_CONFIG maps l1->r1, l2->r2, so its answer sequence is
  # indistinguishable from plain right-item order — useless for proving which one the
  # guarantee compares against. These two cross the mapping instead.
  CROSSED_MATCHING = {
    "left" => [ { "id" => "l1", "text" => "A" }, { "id" => "l2", "text" => "B" },
                { "id" => "l3", "text" => "C" } ],
    "right" => [ { "id" => "r1", "text" => "1" }, { "id" => "r2", "text" => "2" },
                 { "id" => "r3", "text" => "3" } ],
    "pairs" => { "l1" => "r3", "l2" => "r1", "l3" => "r2" }
  }.freeze
  # Three right items for two left ones: the bank is longer than the answer sequence.
  DISTRACTOR_MATCHING = {
    "left" => [ { "id" => "l1", "text" => "A" }, { "id" => "l2", "text" => "B" } ],
    "right" => [ { "id" => "r1", "text" => "1" }, { "id" => "r2", "text" => "2" },
                 { "id" => "r3", "text" => "3" } ],
    "pairs" => { "l1" => "r2", "l2" => "r3" }
  }.freeze

  test "unaligned_items never returns the recorded answer order" do
    question = question_with(:ordering, ORDERING_CONFIG)
    seeds = (1..200)

    # Guard: the plain shuffle has to collide somewhere in this range, or the assertion
    # below would also hold for a reader that does nothing at all.
    collisions = seeds.count do |seed|
      question.shuffled_items(seed).map { |item| item["id"] } == question.correct_order_ids
    end
    assert_operator collisions, :>, 0,
                    "shuffled_items never hit the answer order, so unaligned_items proves nothing here"

    seeds.each do |seed|
      assert_not_equal question.correct_order_ids,
                       question.unaligned_items(seed).map { |item| item["id"] },
                       "seed #{seed} printed the items in the answer order"
    end
  end

  test "unaligned_right_items never lines the bank up with the left column" do
    question = question_with(:matching, CROSSED_MATCHING)
    expected = question.left_items.map { |left| question.pairs[left["id"]] }
    seeds = (1..200)

    # The mapping is crossed, so this cannot be satisfied by plain right-item order.
    assert_not_equal question.right_items.map { |right| right["id"] }, expected

    collisions = seeds.count do |seed|
      question.shuffled_right_items(seed).first(expected.size).map { |right| right["id"] } == expected
    end
    assert_operator collisions, :>, 0,
                    "shuffled_right_items never lined up, so unaligned_right_items proves nothing here"

    seeds.each do |seed|
      assert_not_equal expected,
                       question.unaligned_right_items(seed).first(expected.size).map { |right| right["id"] },
                       "seed #{seed} lettered the bank in answer order"
    end
  end

  test "a bank longer than the left column still never answers it in reading order" do
    question = question_with(:matching, DISTRACTOR_MATCHING)
    expected = question.left_items.map { |left| question.pairs[left["id"]] }

    (1..200).each do |seed|
      assert_not_equal expected,
                       question.unaligned_right_items(seed).first(expected.size).map { |right| right["id"] },
                       "seed #{seed} answered the left column despite the distractor"
    end
  end

  # The security review that produced FR-8 also produced its limit: with two entries there
  # is exactly one order that is not the key, so refusing the key would print its reverse
  # every time and a student who knows the rule reads it backwards. An even chance is the
  # best available at that size, so the draw is kept.
  test "a two-entry bank keeps the plain draw rather than always reversing the key" do
    question = question_with(:matching, MATCHING_CONFIG)
    answer = question.left_items.map { |left| question.pairs[left["id"]] }
    banks = (1..200).map { |seed| question.unaligned_right_items(seed).map { |right| right["id"] } }

    assert_equal 2, banks.uniq.size, "a two-item bank has two orders and both must occur"
    assert_includes banks, answer,
                    "never printing the answer order of a two-item bank makes the reverse a certainty"
  end

  test "a redraw is not one fixed transform of the answer order" do
    question = question_with(:ordering, ORDERING_CONFIG)
    redrawn = (1..600).select do |seed|
      question.shuffled_items(seed).map { |item| item["id"] } == question.correct_order_ids
    end.map { |seed| question.unaligned_items(seed).map { |item| item["id"] } }

    assert_operator redrawn.size, :>, 5, "too few collisions in range to judge the redraw"
    assert_operator redrawn.uniq.size, :>, 1,
                    "every redraw gave the same order, so undoing one public transform names the key"
  end

  test "an unaligned shuffle is stable for one seed and keeps every entry exactly once" do
    ordering = question_with(:ordering, ORDERING_CONFIG)
    matching = question_with(:matching, CROSSED_MATCHING)

    assert_equal ordering.unaligned_items(7), ordering.unaligned_items(7)
    assert_equal matching.unaligned_right_items(7), matching.unaligned_right_items(7)

    assert_equal ordering.correct_order_ids.sort,
                 ordering.unaligned_items(7).map { |item| item["id"] }.sort
    assert_equal matching.student_facing_right.map { |right| right["id"] }.sort,
                 matching.unaligned_right_items(7).map { |right| right["id"] }.sort
  end

  test "the unaligned readers carry id and text only" do
    ordering = question_with(:ordering, ORDERING_CONFIG)
    matching = question_with(:matching, CROSSED_MATCHING)

    assert_equal [ %w[id text] ], ordering.unaligned_items(3).map(&:keys).uniq
    assert_equal [ %w[id text] ], matching.unaligned_right_items(3).map(&:keys).uniq
  end

  private

  def question_with(type, config)
    @exam.questions.create!(
      question_type: type,
      prompt: "Prompt",
      points: 1,
      position: @exam.questions.count,
      config: config.deep_dup
    )
  end

  def publish(question)
    question.exam.publish!
    question.reload
  end

  def assert_structure_frozen(question)
    assert_not question.valid?, "expected the published question to refuse this change"
    assert_includes question.errors[:base],
      I18n.t("activerecord.errors.models.question.attributes.base.structure_frozen")
  end
end
