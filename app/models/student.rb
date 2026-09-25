class Student < ApplicationRecord
  belongs_to :teacher, class_name: "User", inverse_of: :students
  has_many :class_memberships, dependent: :destroy
  has_many :class_groups, through: :class_memberships
  has_many :assignments, dependent: :destroy
  has_many :attempts, through: :assignments
  has_many :credit_entries, dependent: :destroy

  normalizes :telegram_username, with: ->(value) { value.strip.delete_prefix("@").downcase.presence }

  validates :name, presence: true
  validates :telegram_username, format: { with: /\A[a-z][a-z0-9_]{3,31}\z/ },
    uniqueness: { scope: :teacher_id }, allow_nil: true
  validates :telegram_chat_id, uniqueness: { scope: :teacher_id }, allow_nil: true

  before_update :clear_pending_telegram_on_username_change

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def credit_balance
    credit_entries.sum(:amount)
  end

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end

  def telegram_connection_status
    return "connected" if telegram_chat_id.present?
    return "pending" if telegram_pending_chat_id.present?

    "disconnected"
  end

  private

  def clear_pending_telegram_on_username_change
    if will_save_change_to_telegram_username?
      self.telegram_pending_chat_id = nil
      self.telegram_pending_name = nil
    end
  end
end
