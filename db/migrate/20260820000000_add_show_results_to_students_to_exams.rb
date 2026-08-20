class AddShowResultsToStudentsToExams < ActiveRecord::Migration[8.1]
  def change
    add_column :exams, :show_results_to_students, :boolean, default: false, null: false
  end
end
