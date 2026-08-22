class CreateCreditEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :credit_entries do |t|
      t.references :student, null: false, foreign_key: true
      t.references :assignment, null: false, foreign_key: true
      t.integer :amount, null: false
      t.timestamps
    end
  end
end
