require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  ICON_PARTIAL = Rails.root.join("app/views/shared/_icon.html.erb")

  # Reading the branches out of the partial rather than listing them here means a new
  # icon is covered the moment it is drawn, and a deleted one cannot leave a stale name
  # passing behind it.
  test "every icon the partial names draws something" do
    names = icon_names

    assert_operator names.size, :>=, 9, "the app's icon set should not have shrunk silently"

    names.each do |name|
      svg = Nokogiri::HTML5.fragment(ui_icon(name))

      assert svg.css("svg path").any?, "the #{name} icon renders an svg with nothing drawn in it"
    end
  end

  test "an icon name with no branch raises instead of rendering an empty svg" do
    # Rails wraps anything raised inside a template, so the ArgumentError arrives as the cause.
    error = assert_raises(ActionView::Template::Error) { ui_icon("no-such-icon") }

    assert_instance_of ArgumentError, error.cause
    assert_match "no-such-icon", error.message
  end

  private

  def icon_names
    ICON_PARTIAL.read.scan(/when "([a-z_]+)"/).flatten
  end
end
