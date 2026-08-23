require "test_helper"

# The `@theme` block claims every text token clears AA on the surface it sits on. Nothing
# enforced that until this file, and the Mesopotamian palette is exactly the kind of change
# that quietly breaks it: earth tones fail by drifting into brown-on-beige at 3:1.
#
# The palette is rotated by moving hue and chroma while holding each token's oklch lightness,
# so the ladder that was already AA stays AA. These pairs are the ones the components in
# application.css actually form — a pair with no component behind it would be a ratio nobody
# can see.
class PaletteContrastTest < ActiveSupport::TestCase
  STYLESHEET = Rails.root.join("app/assets/tailwind/application.css")

  AA_TEXT = 4.5
  # `ink-subtle` is not a text colour: hairlines, list markers and icon strokes only.
  AA_NON_TEXT = 3.0

  WHITE = "#fff".freeze

  # [foreground, background, minimum ratio, the component that forms the pair]
  PAIRS = [
    # Body text on each of the three surfaces.
    [ "ink", "surface", AA_TEXT, ".source-table td on a hovered row" ],
    [ "ink", "surface-raised", AA_TEXT, ".card-title, .field, .data-table td" ],
    [ "ink", "surface-sunken", AA_TEXT, ".btn-secondary:hover, .nav-link:hover" ],
    [ "ink-light", "surface-raised", AA_TEXT, ".btn-primary:hover fill is ink-light" ],
    [ "ink-muted", "surface", AA_TEXT, ".page-subtitle, .breadcrumbs, .tab" ],
    [ "ink-muted", "surface-raised", AA_TEXT, ".field-hint, .empty-state-message, .nav-link" ],
    [ "ink-muted", "surface-sunken", AA_TEXT, ".badge-neutral, .chip, .data-table th, .order-position" ],

    # Not text, so the lower bar — but it still has to be visible.
    [ "ink-subtle", "surface-raised", AA_NON_TEXT, ".order-handle, marker:text-ink-subtle" ],
    [ "ink-subtle", "surface", AA_NON_TEXT, ".breadcrumb-sep" ],

    # Solid fills: the label is white, so the fill carries the contrast.
    [ WHITE, "ink", AA_TEXT, ".btn-primary, .countdown" ],
    [ WHITE, "ink-light", AA_TEXT, ".btn-primary:hover" ],
    [ WHITE, "accent", AA_TEXT, ".order-item[aria-selected] .order-position" ],
    [ WHITE, "danger", AA_TEXT, ".countdown[data-urgency=urgent]" ],

    # Accent: links, focus, the current state.
    [ "accent", "surface", AA_TEXT, ".link on the page background" ],
    [ "accent", "surface-raised", AA_TEXT, ".link in a card, .list-row-title:hover" ],
    [ "accent", "accent-soft", AA_TEXT, ".page-icon, .option:has(input:checked)" ],
    [ "accent-strong", "accent-soft", AA_TEXT, ".flash-info" ],
    [ "ink", "accent-soft", AA_TEXT, ".option text on the checked row" ],

    # Status colours, each on its own -soft and on a raised surface.
    [ "success", "success-soft", AA_TEXT, ".badge-success, .btn.is-copied" ],
    [ "success-strong", "success-soft", AA_TEXT, ".flash-notice" ],
    [ "success", "surface-raised", AA_TEXT, ".autosave-status[data-state=saved]" ],
    [ "danger", "danger-soft", AA_TEXT, ".badge-danger, .flash-alert, .field-error" ],
    [ "danger", "surface-raised", AA_TEXT, ".btn-danger, .countdown-cell[data-urgency=urgent]" ],
    [ "warning", "warning-soft", AA_TEXT, ".badge-warning, .flash-warning" ],
    [ "warning", "surface-raised", AA_TEXT, "a warning badge lifted onto a card" ],
    [ "info", "info-soft", AA_TEXT, ".badge-info" ],
    [ "info", "surface-raised", AA_TEXT, "an info badge lifted onto a card" ]
  ].freeze

  # The six type stripes are 3px of border on the student runner. Hue is a second signal
  # there — `take/runs/show.html.erb` names the type in a chip beside it — so the bar is
  # visibility against the card, not AA.
  QTYPE_TOKENS = %w[
    qtype-mcq qtype-short-text qtype-open qtype-ordering qtype-matching qtype-source
  ].freeze

  # Hairlines are exempt from the 3:1 bar — they divide content, they do not identify a
  # control, and the printed sheet restates them as #000 anyway. The floor here only catches
  # a rotation that washed the borders off the page entirely.
  HAIRLINE_TOKENS = %w[line line-strong].freeze
  VISIBLE_HAIRLINE = 1.15

  # Roughly the gap between two mid-chroma tokens 25° apart — close enough to catch a real
  # collision, loose enough that the set is not forced onto a colour wheel.
  DISTINCT_STRIPE = 0.04

  setup do
    @tokens = parse_theme_tokens
  end

  test "every token a pair names is defined in the @theme block" do
    named = PAIRS.flat_map { |fg, bg, _, _| [ fg, bg ] }.reject { |value| value.start_with?("#") }
    missing = (named + QTYPE_TOKENS + HAIRLINE_TOKENS).uniq - @tokens.keys

    assert_empty missing, "pairs reference tokens that @theme does not define: #{missing.join(', ')}"
  end

  test "text tokens clear their WCAG minimum on the surface they sit on" do
    failures = PAIRS.filter_map do |foreground, background, minimum, component|
      ratio = contrast(foreground, background)
      next if ratio >= minimum

      format("%s on %s is %.2f:1, needs %.1f:1 — %s", foreground, background, ratio, minimum, component)
    end

    assert_empty failures, "contrast regressions:\n#{failures.join("\n")}"
  end

  test "hairlines stay visible against the surfaces they divide" do
    failures = HAIRLINE_TOKENS.filter_map do |token|
      ratio = contrast(token, "surface-raised")
      next if ratio >= VISIBLE_HAIRLINE

      format("%s is %.2f:1 against a card, the border has washed out", token, ratio)
    end

    assert_empty failures, failures.join("\n")
  end

  test "question-type stripes stay visible against the card they sit on" do
    failures = QTYPE_TOKENS.filter_map do |token|
      ratio = contrast(token, "surface-raised")
      next if ratio >= 1.4

      format("%s is %.2f:1 against the card, too faint to read as a stripe", token, ratio)
    end

    assert_empty failures, failures.join("\n")
  end

  test "question-type stripes are distinguishable from one another" do
    collisions = QTYPE_TOKENS.combination(2).filter_map do |left, right|
      distance = perceptual_distance(left, right)
      next if distance >= DISTINCT_STRIPE

      format("%s and %s are %.3f apart in OKLab, too close to tell apart at 3px", left, right, distance)
    end

    assert_empty collisions, collisions.join("\n")
  end

  private

  def parse_theme_tokens
    css = STYLESHEET.read
    theme = css[/@theme\s*\{(.*?)\n\}/m, 1]

    assert theme, "could not find the @theme block in #{STYLESHEET}"

    theme.scan(/--color-([a-z0-9-]+):\s*([^;]+);/).to_h { |name, value| [ name, value.strip ] }
  end

  def contrast(foreground, background)
    darker, lighter = [ luminance(foreground), luminance(background) ].minmax

    (lighter + 0.05) / (darker + 0.05)
  end

  def luminance(name)
    red, green, blue = linear_rgb(resolve(name))

    (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
  end

  # The stripes are mixed at one lightness, so everything separating them lives in the OKLab
  # a/b plane. Measuring the plane rather than the hue angle is what lets a near-neutral sit
  # next to a saturated token at the same hue: `qtype-source` is clay at chroma 0.02 and
  # `qtype-short-text` is gold at 0.11, ten degrees apart and in no danger of being confused.
  def perceptual_distance(left, right)
    (a1, b1), (a2, b2) = [ left, right ].map { |token| oklab_ab(resolve(token)) }

    Math.hypot(a1 - a2, b1 - b2)
  end

  def oklab_ab(value)
    _, chroma, hue = value.match(/\Aoklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\)\z/).captures.map(&:to_f)
    radians = hue * Math::PI / 180

    [ chroma * Math.cos(radians), chroma * Math.sin(radians) ]
  end

  def resolve(name)
    return name if name.start_with?("#")

    @tokens.fetch(name)
  end

  def linear_rgb(value)
    case value
    when /\Aoklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\)\z/ then oklch_to_linear_rgb($1.to_f, $2.to_f, $3.to_f)
    when /\A#(\h{3})\z/ then hex_to_linear_rgb($1.chars.map { |c| (c * 2).hex })
    when /\A#(\h{6})\z/ then hex_to_linear_rgb($1.scan(/\h{2}/).map(&:hex))
    else raise ArgumentError, "unsupported colour value: #{value}"
    end
  end

  # Björn Ottosson's OKLab → linear sRGB. The matrix lands in linear light, which is what
  # WCAG luminance wants, so there is no gamma step on this path — only the clamp, because
  # a high-chroma token can compute outside the gamut a screen can show.
  def oklch_to_linear_rgb(lightness, chroma, hue)
    radians = hue * Math::PI / 180
    a = chroma * Math.cos(radians)
    b = chroma * Math.sin(radians)

    long   = (lightness + (0.3963377774 * a) + (0.2158037573 * b))**3
    medium = (lightness - (0.1055613458 * a) - (0.0638541728 * b))**3
    short  = (lightness - (0.0894841775 * a) - (1.2914855480 * b))**3

    [
      (4.0767416621 * long) - (3.3077115913 * medium) + (0.2309699292 * short),
      (-1.2684380046 * long) + (2.6097574011 * medium) - (0.3413193965 * short),
      (-0.0041960863 * long) - (0.7034186147 * medium) + (1.7076147010 * short)
    ].map { |channel| channel.clamp(0.0, 1.0) }
  end

  def hex_to_linear_rgb(channels)
    channels.map do |channel|
      value = channel / 255.0

      value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end
  end
end
