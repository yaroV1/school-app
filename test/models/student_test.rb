require "test_helper"

class StudentTest < ActiveSupport::TestCase
  test "Telegram usernames are optional normalized unique per teacher and validated" do
    student = users(:one).students.create!(name: "Ada", telegram_username: " @Ada_123 ")
    assert_equal "ada_123", student.telegram_username
    duplicate = users(:one).students.new(name: "Duplicate", telegram_username: "ADA_123")
    assert_not duplicate.valid?
    assert duplicate.errors.added?(:telegram_username, :taken, value: "ada_123")
    assert users(:two).students.create!(name: "Ada", telegram_username: "ADA_123")
    student.telegram_username = "https://t.me/ada_123"
    assert_not student.valid?
    student.update!(telegram_username: " ")
    assert_nil student.telegram_username
    assert users(:one).students.create!(name: "No username")
  end

  test "editing nickname invalidates a pending request but retains a confirmed ID" do
    student = users(:one).students.create!(name: "Ada", telegram_username: "ada_123",
      telegram_pending_chat_id: 123, telegram_pending_name: "Old claimant")
    student.update!(telegram_username: "new_name")
    assert_nil student.telegram_pending_chat_id
    assert_nil student.telegram_pending_name
    student.update!(telegram_chat_id: 456)
    student.update!(telegram_username: "changed_name")
    assert_equal 456, student.telegram_chat_id
  end
end
