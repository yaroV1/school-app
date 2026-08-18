class Question < ApplicationRecord
  PHOTO_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
  PHOTO_MAX_BYTES = 8.megabytes
  TEXT_BEARING_KEYS = %w[options items left right].freeze

  belongs_to :exam, inverse_of: :questions
  has_many :answers, dependent: :destroy
  has_one_attached :photo

  enum :question_type, { mcq: 0, short_text: 1, open: 2, ordering: 3, matching: 4, source: 5 }, validate: true

  validates :prompt, presence: true
  validates :points, numericality: { only_integer: true, greater_than: 0 }
  validate :mcq_has_correct_option
  validate :ordering_has_items
  validate :matching_has_pairs
  validate :source_has_text
  validate :acceptable_photo
  validate :structure_unchanged_outside_draft

  def auto_gradable?
    mcq? || ordering? || matching?
  end

  def options
    Array(config["options"])
  end

  def items
    Array(config["items"])
  end

  def left_items
    Array(config["left"])
  end

  def right_items
    Array(config["right"])
  end

  def pairs
    (config["pairs"] || {}).stringify_keys
  end

  def rubric
    config["rubric"]
  end

  def model_answer
    config["model_answer"]
  end

  def source_text
    config["source"].to_s
  end

  def correct_option_id
    options.find { |o| o["is_correct"] }&.dig("id")
  end

  def correct_order_ids
    items.map { |item| item["id"].to_s }
  end

  def student_facing_options
    options.map { |o| o.slice("id", "text") }
  end

  def student_facing_items
    items.map { |item| item.slice("id", "text") }
  end

  def student_facing_left
    left_items.map { |item| item.slice("id", "text") }
  end

  def student_facing_right
    right_items.map { |item| item.slice("id", "text") }
  end

  def shuffled_items(seed)
    student_facing_items.shuffle(random: Random.new(stable_seed(seed, "order")))
  end

  def shuffled_right_items(seed)
    student_facing_right.shuffle(random: Random.new(stable_seed(seed, "match")))
  end

  def display_items_for(answer, seed)
    saved = Array(answer&.order_ids)
    return shuffled_items(seed) if saved.blank?

    indexed = student_facing_items.index_by { |item| item["id"].to_s }
    ordered = saved.map { |id| indexed.delete(id) }.compact
    ordered + indexed.values
  end

  private

  def stable_seed(seed, suffix)
    Digest::SHA256.hexdigest("#{id}:#{seed}:#{suffix}").to_i(16) % (2**31)
  end

  def mcq_has_correct_option
    return unless mcq?

    if options.blank?
      errors.add(:config, :blank_options)
      return
    end

    correct = options.count { |o| o["is_correct"] }
    errors.add(:config, :one_correct) unless correct == 1
  end

  def ordering_has_items
    return unless ordering?

    count = items.size
    if count < 3
      errors.add(:config, :too_few_items)
    elsif count > 8
      errors.add(:config, :too_many_items)
    end
  end

  def matching_has_pairs
    return unless matching?

    errors.add(:config, :too_few_pairs) if left_items.size < 2 || pairs.size < 2
  end

  def source_has_text
    return unless source?

    errors.add(:config, :blank_source) if source_text.strip.blank?
  end

  def acceptable_photo
    return unless photo.attached?

    errors.add(:photo, :invalid_type) unless photo.content_type.in?(PHOTO_TYPES)
    errors.add(:photo, :too_big) if photo.byte_size > PHOTO_MAX_BYTES
  end

  def structure_unchanged_outside_draft
    return if new_record? || exam.nil? || exam.questions_editable?
    return unless structure_moved?

    errors.add(:base, :structure_frozen)
  end

  def structure_moved?
    points_changed? || question_type_changed? || position_changed? ||
      config_skeleton(config_was) != config_skeleton(config)
  end

  def config_skeleton(raw)
    skeleton = raw || {}
    skeleton = skeleton.except("source") if source?
    TEXT_BEARING_KEYS.each do |key|
      next unless skeleton.key?(key)

      entries = Array(skeleton[key]).map { |entry| entry.is_a?(Hash) ? entry.except("text") : entry }
      skeleton = skeleton.merge(key => entries)
    end
    skeleton
  end
end
