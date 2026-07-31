# frozen_string_literal: true

require_relative "coatepec/version"
require_relative "coatepec/errors"
require_relative "coatepec/project_config"
require_relative "coatepec/project"
require_relative "coatepec/spec/path_policy"
require_relative "coatepec/protocol"
require_relative "coatepec/worker/change_detector"
require_relative "coatepec/worker/client"
require_relative "coatepec/worker/rails_runtime"
require_relative "coatepec/spec/result"
require_relative "coatepec/spec/process_strategy"
require_relative "coatepec/spec/fork_strategy"
require_relative "coatepec/spec/spawn_strategy"
require_relative "coatepec/spec/runner"
require_relative "coatepec/worker/server"
require_relative "coatepec/worker_manager"

# Coatepec is a local stdio MCP sidecar that keeps an isolated Rails test
# worker warm so coding agents can run targeted RSpec examples quickly,
# without exposing a general Rails console.
module Coatepec
end
