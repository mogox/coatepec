# frozen_string_literal: true

require_relative "../../coatepec"

module Coatepec
  module MCP
    # Fills a tool's omitted inputs: call argument first, then .coatepec.yml, then the built-in.
    module Defaults
      BUILTIN = {
        spec_run: { include_passing: false, include_stdout: "failures", timeout_seconds: 120 },
        routes: { engines: Introspection::Routes::DEFAULT_ENGINES }
      }.freeze

      module_function

      # Re-reads the file each call: a few hundred bytes, and an edit then applies to the next call.
      def resolve(tool, project_root, **given)
        configured = ProjectConfig.new(project_root).defaults_for(tool)
        BUILTIN.fetch(tool).to_h do |key, builtin|
          [key, given[key].nil? ? configured.fetch(key, builtin) : given[key]]
        end
      end
    end
  end
end
