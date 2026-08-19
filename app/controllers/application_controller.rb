require "csv"

class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

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
