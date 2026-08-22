class CreditEntry < ApplicationRecord
  belongs_to :student
  belongs_to :assignment

  validates :amount, numericality: { only_integer: true }
end
