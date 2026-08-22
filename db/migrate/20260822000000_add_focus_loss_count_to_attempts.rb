class AddFocusLossCountToAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :attempts, :focus_loss_count, :integer, default: 0, null: false
  end
end
