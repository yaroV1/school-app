# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_22_010000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "answers", force: :cascade do |t|
    t.integer "attempt_id", null: false
    t.decimal "auto_score", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.json "payload", default: {}, null: false
    t.integer "question_id", null: false
    t.text "teacher_comment"
    t.decimal "teacher_score", precision: 8, scale: 2
    t.datetime "updated_at", null: false
    t.index ["attempt_id", "question_id"], name: "index_answers_on_attempt_id_and_question_id", unique: true
    t.index ["attempt_id"], name: "index_answers_on_attempt_id"
    t.index ["question_id"], name: "index_answers_on_question_id"
  end

  create_table "assignments", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "created_at", null: false
    t.integer "exam_id", null: false
    t.datetime "revoked_at"
    t.integer "student_id", null: false
    t.datetime "updated_at", null: false
    t.index ["access_token"], name: "index_assignments_on_access_token", unique: true
    t.index ["exam_id", "student_id"], name: "index_assignments_on_exam_id_and_student_id", unique: true
    t.index ["exam_id"], name: "index_assignments_on_exam_id"
    t.index ["student_id"], name: "index_assignments_on_student_id"
  end

  create_table "attempts", force: :cascade do |t|
    t.integer "assignment_id", null: false
    t.integer "attempt_no", null: false
    t.datetime "created_at", null: false
    t.datetime "deadline_at"
    t.integer "focus_loss_count", default: 0, null: false
    t.datetime "last_activity_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "started_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "submitted_at"
    t.datetime "updated_at", null: false
    t.index ["assignment_id", "attempt_no"], name: "index_attempts_on_assignment_id_and_attempt_no", unique: true
    t.index ["assignment_id"], name: "index_attempts_on_assignment_id"
  end

  create_table "class_groups", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "teacher_id", null: false
    t.datetime "updated_at", null: false
    t.index ["teacher_id"], name: "index_class_groups_on_teacher_id"
  end

  create_table "class_memberships", force: :cascade do |t|
    t.integer "class_group_id", null: false
    t.datetime "created_at", null: false
    t.integer "student_id", null: false
    t.datetime "updated_at", null: false
    t.index ["class_group_id", "student_id"], name: "index_class_memberships_on_class_group_id_and_student_id", unique: true
    t.index ["class_group_id"], name: "index_class_memberships_on_class_group_id"
    t.index ["student_id"], name: "index_class_memberships_on_student_id"
  end

  create_table "credit_entries", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "assignment_id", null: false
    t.datetime "created_at", null: false
    t.integer "student_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignment_id"], name: "index_credit_entries_on_assignment_id"
    t.index ["student_id"], name: "index_credit_entries_on_student_id"
  end

  create_table "exams", force: :cascade do |t|
    t.datetime "available_from"
    t.datetime "available_until"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "max_attempts", default: 1, null: false
    t.boolean "show_results_to_students", default: false, null: false
    t.integer "status", default: 0, null: false
    t.integer "subject_id", null: false
    t.integer "teacher_id", null: false
    t.integer "time_limit_sec"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_id"], name: "index_exams_on_subject_id"
    t.index ["teacher_id"], name: "index_exams_on_teacher_id"
  end

  create_table "grades", force: :cascade do |t|
    t.integer "attempt_id", null: false
    t.datetime "created_at", null: false
    t.datetime "finalized_at"
    t.boolean "finalized_by_teacher", default: false, null: false
    t.decimal "max_score", precision: 8, scale: 2, null: false
    t.text "teacher_comment"
    t.decimal "total_score", precision: 8, scale: 2
    t.datetime "updated_at", null: false
    t.index ["attempt_id"], name: "index_grades_on_attempt_id", unique: true
  end

  create_table "questions", force: :cascade do |t|
    t.json "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "exam_id", null: false
    t.integer "points", default: 1, null: false
    t.integer "position", default: 0, null: false
    t.text "prompt", null: false
    t.integer "question_type", null: false
    t.datetime "updated_at", null: false
    t.index ["exam_id"], name: "index_questions_on_exam_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "students", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.integer "teacher_id", null: false
    t.datetime "updated_at", null: false
    t.index ["teacher_id"], name: "index_students_on_teacher_id"
  end

  create_table "subjects", force: :cascade do |t|
    t.integer "class_group_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["class_group_id", "name"], name: "index_subjects_on_class_group_id_and_name", unique: true
    t.index ["class_group_id"], name: "index_subjects_on_class_group_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "answers", "attempts"
  add_foreign_key "answers", "questions"
  add_foreign_key "assignments", "exams"
  add_foreign_key "assignments", "students"
  add_foreign_key "attempts", "assignments"
  add_foreign_key "class_groups", "users", column: "teacher_id"
  add_foreign_key "class_memberships", "class_groups"
  add_foreign_key "class_memberships", "students"
  add_foreign_key "credit_entries", "assignments"
  add_foreign_key "credit_entries", "students"
  add_foreign_key "exams", "subjects"
  add_foreign_key "exams", "users", column: "teacher_id"
  add_foreign_key "grades", "attempts"
  add_foreign_key "questions", "exams"
  add_foreign_key "sessions", "users"
  add_foreign_key "students", "users", column: "teacher_id"
  add_foreign_key "subjects", "class_groups"
end
