# frozen_string_literal: true

module Coatepec
  module TestUnit
    # Makes `file:LINE` selectors work regardless of the target app's Rails/
    # Minitest pairing. Rails installs its own Rails::LineFiltering only via
    # Rails::TestUnitRailtie, which an app generated with --skip-test never
    # loads; and Rails 7.1's version overrides `run`, a method Minitest 6 no
    # longer calls (it dispatches through `run_suite` and reads
    # options[:include], not options[:filter]). So the child always extends
    # ActiveSupport::TestCase with the one method the *running* Minitest
    # actually calls, composing Rails::TestUnit::Runner's recorded line
    # filters through Rails' public compose_filter. Stacking on top of
    # Rails' own module is idempotent: CompositeFilter#derive_named_filter
    # unwraps an existing composite via #named_filter.
    #
    # Exactly one method per module, never both: on Minitest 6 a class-level
    # `run` override intercepts an unrelated 3-argument call and raises.
    module LineFiltering
      MT6 = Module.new do
        def run_suite(reporter, options = {})
          options = options.merge(include: ::Rails::TestUnit::Runner.compose_filter(self, options[:include]))
          super(reporter, options)
        end
      end

      MT5 = Module.new do
        def run(reporter, options = {})
          options = options.merge(filter: ::Rails::TestUnit::Runner.compose_filter(self, options[:filter]))
          super(reporter, options)
        end
      end

      def self.module_for(minitest_version)
        minitest_version.start_with?("6") ? MT6 : MT5
      end

      # Ruby ignores a second `extend` of a module already in the singleton
      # ancestors, so calling this more than once per process is harmless.
      def self.install!
        require "rails/test_unit/runner"
        ::ActiveSupport::TestCase.extend(module_for(::Minitest::VERSION))
      end
    end
  end
end
