module ApplicationHelper
  def nav_class(path)
    base = "hover:text-slate-900"
    current_page?(path) ? "#{base} text-slate-900 underline underline-offset-4" : "#{base} text-slate-600"
  end

  def btn_primary
    "inline-flex items-center rounded-md bg-slate-900 px-3 py-2 text-sm font-medium text-white hover:bg-slate-700"
  end

  def btn_secondary
    "inline-flex items-center rounded-md border border-slate-300 bg-white px-3 py-2 text-sm font-medium text-slate-800 hover:bg-slate-50"
  end

  def field_class
    "mt-1 block w-full rounded-md border border-slate-300 px-3 py-2 shadow-sm focus:border-slate-500 focus:outline-none"
  end

  def status_badge(status)
    colors = {
      "draft" => "bg-slate-100 text-slate-700",
      "published" => "bg-emerald-100 text-emerald-800",
      "closed" => "bg-amber-100 text-amber-800",
      "not_started" => "bg-slate-100 text-slate-600",
      "in_progress" => "bg-sky-100 text-sky-800",
      "submitted" => "bg-emerald-100 text-emerald-800",
      "expired" => "bg-orange-100 text-orange-800",
      "revoked" => "bg-red-100 text-red-700",
      "abandoned" => "bg-slate-100 text-slate-600"
    }
    content_tag(:span, t("statuses.#{status}"), class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{colors[status.to_s] || 'bg-slate-100'}")
  end
end
