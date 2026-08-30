require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "refuses a password under the minimum length" do
    user = User.new(email_address: "short@example.com", password: "a" * (User::MINIMUM_PASSWORD_LENGTH - 1))

    assert_not user.valid?
    assert user.errors.of_kind?(:password, :too_short)
  end

  test "accepts a password at the minimum length" do
    user = User.new(email_address: "exact@example.com", password: "a" * User::MINIMUM_PASSWORD_LENGTH)

    assert_predicate user, :valid?
  end

  # An update that leaves the password alone reads it back as nil, which is why the floor is
  # allow_nil: without that, editing anything else on a teacher would fail validation.
  test "stays valid when an update does not touch the password" do
    assert users(:one).update(email_address: "renamed@example.com")
  end
end
