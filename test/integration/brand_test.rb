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

  # The student layout gets the same assertion where its setup already exists, in
  # mvp_flow_test's teacher→student spine.
  test "the teacher shell preloads the heading face from this app, not from a CDN" do
    sign_in_as @teacher
    get class_groups_url
    assert_font_self_hosted

    delete session_url
    get new_session_url
    assert_font_self_hosted
  end

  test "the stylesheet declares the heading face against local files only" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    sources = css.scan(/src:\s*url\(([^)]*)\)/).flatten

    assert_equal 2, sources.size, "one variable file per script — Latin and Cyrillic"
    sources.each do |source|
      refute_match %r{https?://}, source, "the heading face is fetched over the network"
      assert Rails.root.join("app/assets/fonts", source.delete('"')).exist?,
             "#{source} is declared but not shipped in app/assets/fonts"
    end
  end

  # The scribe appears here and nowhere else: the sign-in page is the only screen with the
  # room to read him at illustration size.
  test "the sign-in page carries the scribe and the app name before a teacher has a session" do
    get new_session_url

    assert_response :success
    assert_select "svg circle", minimum: 1, message: "the scribe's head"
    assert_select "svg path", minimum: 6, message: "the scribe, his tablet and his reed"
    assert_select "p", text: I18n.t("app_name")
  end
end
