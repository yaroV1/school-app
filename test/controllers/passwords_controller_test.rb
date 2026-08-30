require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ]
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice I18n.t("auth.passwords.reset_sent")
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice I18n.t("auth.passwords.reset_sent")
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice I18n.t("auth.passwords.invalid_link")
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token),
        params: { password: "long-enough-secret", password_confirmation: "long-enough-secret" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice I18n.t("auth.passwords.reset_success")
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token),
        params: { password: "long-enough-secret", password_confirmation: "long-enough-secretz" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice I18n.t("auth.passwords.mismatch")
  end

  # Both fields agree here, so the mismatch sentence would send the teacher back to retype the
  # same too-short password. The alert has to name the rule that actually refused it.
  test "update with a password under the minimum length" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "korotkyi", password_confirmation: "korotkyi" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice I18n.t("errors.messages.too_short", count: User::MINIMUM_PASSWORD_LENGTH)
    assert_select "#notice, #alert" do |elements|
      assert_not_includes elements.map(&:text).join, I18n.t("auth.passwords.mismatch")
    end
  end

  private
    def assert_notice(text)
      assert_select "#notice, #alert" do |elements|
        assert_includes elements.map(&:text).join, text
      end
    end
end
