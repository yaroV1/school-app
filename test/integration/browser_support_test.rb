require "test_helper"

# The browser floor reaches the unauthenticated Take:: pages, where a refusal costs a student
# their lesson. These pin the two edges that matter: the phones the floor was lowered to admit
# still get in, and the ones below it get a page they can act on rather than a blank 406.
class BrowserSupportTest < ActionDispatch::IntegrationTest
  IOS_16_4 = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4 like Mac OS X) AppleWebKit/605.1.15 " \
             "(KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1".freeze
  IOS_15_6 = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_6 like Mac OS X) AppleWebKit/605.1.15 " \
             "(KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1".freeze
  CHROME_111 = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) " \
               "Chrome/111.0.0.0 Mobile Safari/537.36".freeze
  CHROME_105 = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) " \
               "Chrome/105.0.0.0 Mobile Safari/537.36".freeze

  setup do
    @teacher = users(:one)
    @exam = create_exam!(@teacher, title: "Quiz", status: :published)
    @exam.questions.create!(question_type: :short_text, prompt: "Capital?", points: 1, position: 0)
    student = @teacher.students.create!(name: "Lin")
    @token = @exam.assignments.create!(student: student).access_token
  end

  # Both of these were refused by Rails' :modern set. iOS 16 is where a large share of school
  # phones stopped, so this is the case the floor was rewritten for.
  test "a student on iOS 16.4 reaches their test" do
    get student_portal_path(token: @token), headers: { "HTTP_USER_AGENT" => IOS_16_4 }

    assert_response :success
  end

  test "a student on Chrome 111 reaches their test" do
    get student_portal_path(token: @token), headers: { "HTTP_USER_AGENT" => CHROME_111 }

    assert_response :success
  end

  test "a student below the floor gets a page they can act on" do
    get student_portal_path(token: @token), headers: { "HTTP_USER_AGENT" => IOS_15_6 }

    assert_response :not_acceptable
    assert_includes response.body, "Цей браузер застарілий"
    # The one line that turns a stuck student into a teacher who knows what happened.
    assert_includes response.body, "покажи цей екран учителю"
    assert_includes response.body, 'lang="uk"'
  end

  test "a teacher below the floor is refused the same way" do
    sign_in_as @teacher

    get class_groups_path, headers: { "HTTP_USER_AGENT" => CHROME_105 }

    assert_response :not_acceptable
  end

  # allow_browser only guards browsers it can name and version, and the page it serves must not
  # depend on the asset pipeline the refused browser cannot use.
  test "the refusal page loads nothing the blocked browser would choke on" do
    get student_portal_path(token: @token), headers: { "HTTP_USER_AGENT" => IOS_15_6 }

    # Comments stripped: the page documents the features it avoids by naming them.
    markup = response.body.gsub(/<!--.*?-->/m, "")
    assert_no_match(/<link[^>]+stylesheet/, markup)
    assert_no_match(/<script/, markup)
    assert_no_match(/oklch\(|color-mix\(|:has\(|dvh/, markup)
  end
end
