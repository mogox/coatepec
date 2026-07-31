# frozen_string_literal: true

module Coatepec
  # Entry point for the `coatepec` executable: parses `--root`/`--debug`/
  # `--version`/`--help`, then runs the MCP server over stdio.
  class CLI
    def self.run(argv)
      options = parse(argv)
      project = Coatepec::Project.new(options[:root] || Dir.pwd)
      worker_manager = Coatepec::WorkerManager.new(project)
      server = Coatepec::MCP.build_server(project: project, worker_manager: worker_manager)
      ::MCP::Server::Transports::StdioTransport.new(server).open
    rescue Coatepec::Error => e
      warn "coatepec: #{e.code}: #{e.message}"
      exit 1
    end

    def self.parse(argv)
      options = { root: nil, debug: false }
      remaining = argv.dup
      while (arg = remaining.shift)
        apply_flag!(options, arg, remaining)
      end
      options
    end

    def self.apply_flag!(options, arg, remaining)
      case arg
      when "--root" then options[:root] = remaining.shift
      when "--debug" then options[:debug] = true
      when "--version" then (puts Coatepec::VERSION
                             exit 0)
      when "--help" then (puts "Usage: coatepec --root PATH [--debug]"
                          exit 0)
      end
    end
    private_class_method :apply_flag!
  end
end
