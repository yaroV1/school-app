class AddPhase11Hardening < ActiveRecord::Migration[8.1]
  def change
    add_column :exams, :available_from, :datetime
    add_column :exams, :available_until, :datetime

    add_column :attempts, :lock_version, :integer, null: false, default: 0
  end
end
