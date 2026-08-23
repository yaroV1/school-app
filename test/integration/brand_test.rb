require "test_helper"

# The brand is spread across two layouts, a shared partial and two static files in public/.
# Nothing tied them together, so a rename could easily reach the header and miss the student
# shell, or the mark could keep rendering an empty <svg> after a bad edit to the partial.
class BrandTest < ActionDispatch::IntegrationTest
  setup do
    @teacher = users(:one)
  end

  test "the teacher shell carries the tablet mark and the app name" do
    sign_in_as @teacher
    get class_groups_url

    assert_response :success
    assert_select ".app-header .brand .brand-mark svg path", minimum: 3,
                  message: "the tablet, its wedges and its rule are three separate paths"
    assert_select ".app-header .brand", text: /#{I18n.t('app_name')}/
  end

  test "the sign-in page carries the mark before a teacher has a session" do
    get new_session_url

    assert_response :success
    assert_select ".brand-mark svg path", minimum: 3
    assert_select "p", text: I18n.t("app_name")
  end
end
