module ApplicationHelper
  STATUS_BADGES = {
    "draft" => "badge-neutral",
    "published" => "badge-success",
    "closed" => "badge-warning",
    "not_started" => "badge-neutral",
    "in_progress" => "badge-info",
    "submitted" => "badge-success",
    "expired" => "badge-warning",
    "revoked" => "badge-danger",
    "abandoned" => "badge-neutral",
    "active" => "badge-success"
  }.freeze

  def btn_primary
    "btn btn-primary"
  end

  def btn_secondary
    "btn btn-secondary"
  end

  def btn_danger
    "btn btn-danger"
  end

  def field_class
    "field"
  end

  # `aria-current` carries the active state, so highlighting is not tied to a
  # particular colour class.
  def nav_link_to(text, path)
    link_to text, path, class: "nav-link", aria: { current: ("page" if current_page?(path)) }
  end

  def tab_link_to(text, path, count: nil)
    link_to path, class: "tab", aria: { current: ("page" if current_page?(path)) } do
      parts = [ text ]
      parts << content_tag(:span, count, class: "tab-count") if count
      safe_join(parts, " ")
    end
  end

  # Same shape the countdown controller writes, so the server-rendered cell and
  # the ticking one never disagree.
  def countdown_display(seconds)
    return t("common.dash") if seconds.nil?

    format("%d:%02d", seconds / 60, seconds % 60)
  end

  def status_badge(status)
    variant = STATUS_BADGES.fetch(status.to_s, "badge-neutral")
    content_tag(:span, t("statuses.#{status}"), class: "badge #{variant}")
  end
end
