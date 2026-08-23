ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def create_exam!(teacher, **attrs)
      subject = attrs.delete(:subject)
      group = attrs.delete(:class_group)
      if subject.nil?
        group ||= teacher.class_groups.first || teacher.class_groups.create!(name: "Class")
        subject = group.subjects.first || group.subjects.create!(name: "Subject")
      end
      teacher.exams.create!({ title: "Quiz", max_attempts: 1, subject: subject }.merge(attrs))
    end

    # Both layouts preload the heading face, and neither may reach a font CDN: that is a
    # second origin on a school network, and a hole in the CSP the day one is switched on.
    def assert_font_self_hosted
      assert_select "link[rel=preload][as=font][type='font/woff2'][href^='/assets/literata-']", 1
      refute_match(/fonts\.(googleapis|gstatic)\.com/, response.body, "the page reaches a font CDN")
    end

    # Swap a module method for the duration of a block. Minitest 6 ships no `minitest/mock`,
    # so there is no Object#stub; used to raise conditions a real race would produce flakily.
    def replacing(mod, name, replacement)
      original = mod.method(name)
      mod.define_singleton_method(name, &replacement)
      yield
    ensure
      mod.define_singleton_method(name, original)
    end

    # Add more helper methods to be used by all tests here...
  end
end
