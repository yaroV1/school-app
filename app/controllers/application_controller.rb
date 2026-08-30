require "csv"

class ApplicationController < ActionController::Base
  include Authentication

  # Rails' :modern set is a generic marker, never measured against this app, and it reaches the
  # unauthenticated Take:: pages too — where being turned away is a student staring at an error
  # instead of the test their class is sitting, with a teacher who cannot debug it mid-lesson.
  # So these floors come from what the pages actually use: oklch() and color-mix() carry the
  # whole palette, import maps load every Stimulus controller, and a single :has() rule is what
  # Firefox waits on. Opera 97 is Chromium 111. Tailwind guards its @property block behind
  # @supports, so that one sets no floor. Against :modern this admits Safari 16.4-17.1 — every
  # iPhone that stopped at iOS 16 — and Chrome 111-119.
  SUPPORTED_BROWSERS = { safari: 16.4, chrome: 111, firefox: 121, opera: 97, ie: false }.freeze

  allow_browser versions: SUPPORTED_BROWSERS

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # BOM + ";" so Excel on Windows opens Ukrainian names; comma is the decimal mark.
  def send_csv(filename, headers, rows)
    body = CSV.generate(col_sep: ";", encoding: Encoding::UTF_8) do |csv|
      csv << headers
      rows.each { |row| csv << row }
    end
    send_data "\uFEFF#{body}", filename: filename, type: "text/csv; charset=utf-8"
  end

  def csv_time(time)
    time ? I18n.l(time, format: :short) : ""
  end

  def csv_decimal(value)
    value.nil? ? "" : value.to_d.to_s("F")
  end
end
