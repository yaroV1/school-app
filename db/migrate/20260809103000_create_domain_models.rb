class CreateDomainModels < ActiveRecord::Migration[8.1]
  def change
    create_table :students do |t|
      t.references :teacher, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :email
      t.datetime :archived_at
      t.timestamps
    end

    create_table :class_groups do |t|
      t.references :teacher, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.timestamps
    end

    create_table :class_memberships do |t|
      t.references :class_group, null: false, foreign_key: true
      t.references :student, null: false, foreign_key: true
      t.timestamps
    end
    add_index :class_memberships, %i[class_group_id student_id], unique: true

    # Named "exams" to avoid clashing with Minitest's Test constant; UI/routes still say "tests".
    create_table :exams do |t|
      t.references :teacher, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.integer :time_limit_sec
      t.integer :max_attempts, null: false, default: 1
      t.timestamps
    end

    create_table :questions do |t|
      t.references :exam, null: false, foreign_key: true
      t.integer :question_type, null: false
      t.text :prompt, null: false
      t.integer :points, null: false, default: 1
      t.integer :position, null: false, default: 0
      t.json :config, null: false, default: {}
      t.timestamps
    end

    create_table :assignments do |t|
      t.references :exam, null: false, foreign_key: true
      t.references :student, null: false, foreign_key: true
      t.string :access_token, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :assignments, :access_token, unique: true
    add_index :assignments, %i[exam_id student_id], unique: true

    create_table :attempts do |t|
      t.references :assignment, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :attempt_no, null: false
      t.datetime :started_at, null: false
      t.datetime :deadline_at
      t.datetime :submitted_at
      t.datetime :last_activity_at, null: false
      t.timestamps
    end
    add_index :attempts, %i[assignment_id attempt_no], unique: true

    create_table :answers do |t|
      t.references :attempt, null: false, foreign_key: true
      t.references :question, null: false, foreign_key: true
      t.json :payload, null: false, default: {}
      t.decimal :auto_score, precision: 8, scale: 2
      t.decimal :teacher_score, precision: 8, scale: 2
      t.text :teacher_comment
      t.timestamps
    end
    add_index :answers, %i[attempt_id question_id], unique: true

    create_table :grades do |t|
      t.references :attempt, null: false, foreign_key: true, index: { unique: true }
      t.decimal :total_score, precision: 8, scale: 2
      t.decimal :max_score, precision: 8, scale: 2, null: false
      t.text :teacher_comment
      t.boolean :finalized_by_teacher, null: false, default: false
      t.datetime :finalized_at
      t.timestamps
    end
  end
end
