require "test_helper"

# Variant A lives in the component layer of application.css. A template can keep
# the right class names and still ship a boxed page if those rules grow a border
# or a tile back. This file reads the stylesheet the same way the contrast suite
# does, so the airy contract is pinned to source, not to a rendered page.
class ChromeTest < ActiveSupport::TestCase
  STYLESHEET = Rails.root.join("app/assets/tailwind/application.css")

  setup do
    @css = STYLESHEET.read
  end

  test "page titles stay serif and at least 3xl" do
    body = rule(".page-title")

    assert_includes body, "font-serif"
    assert_match(/\btext-3xl\b|\btext-4xl\b/, body)
  end

  test "the header and the tab bar group by space, not a hairline" do
    refute_includes rule(".app-header"), "border-b"
    refute_includes rule(".tab-bar"), "border-b"
    refute_includes rule(".tab"), "border-b-2"
  end

  test "lists are not a boxed, divided tile" do
    body = rule(".list")

    refute_includes body, "divide-y"
    refute_includes body, "shadow-card"
    refute_includes body, "rounded-card"
  end

  test "a question card has no left stripe" do
    refute_includes rule(".qcard"), "border-l-[3px]"
  end

  test "the current tab and the question legend mark themselves with the wedge" do
    assert_includes rule('.tab[aria-current="page"]::before'), "var(--wedge)"
    assert_includes rule(".qcard-legend::before"), "var(--wedge)"
  end

  test "cuneiform grain is not a body background" do
    refute_includes rule("body"), "cuneiform.svg"
  end

  test "the printed sheet keeps the former 2xl title size" do
    print_css = @css[/@media print\s*\{(.*)\}\s*\z/m, 1]

    assert print_css, "the print block is missing"
    assert_includes print_css, ".print-sheet .page-title"
    assert_includes print_css, "font-size: 1.5rem"
  end

  private

  def rule(selector)
    pattern = /#{Regexp.escape(selector)}\s*\{([^}]*)\}/
    match = @css.match(pattern)

    assert match, "could not find #{selector} in #{STYLESHEET}"
    match[1]
  end
end
