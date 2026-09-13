# frozen_string_literal: true

module Coatepec
  module Worker
    # The test worker's message loop: reads NDJSON requests from its parent
    # over Protocol, lazily boots Rails on first use, dispatches `status`/
    # `spec_run`, and writes back structured ok/error responses.
    class Server
      def initialize(project_root, input:, protocol_output:)
        @protocol = Protocol.new(input: input, output: protocol_output)
        @runtime = RailsRuntime.new(project_root)
        @project_root = project_root
      end

      def run
        loop do
          message = @protocol.read
          break if message.nil?

          handle(message)
        end
      end

      private

      def handle(message)
        @runtime.boot! unless @runtime.booted?

        data = dispatch(message[:command], message[:args] || {})
        @protocol.write(id: message[:id], ok: true, data: data)
      rescue Coatepec::Error => e
        @protocol.write(id: message[:id], ok: false, error: { code: e.code, message: e.message, details: e.details })
      rescue StandardError => e
        @protocol.write(id: message[:id], ok: false, error: { code: :internal_error, message: e.message, details: {} })
      end

      def dispatch(command, args)
        Rails.application.reloader.wrap { execute_command(command, args) }
      end

      def execute_command(command, args)
        case command
        when "status" then @runtime.status
        when "spec_run" then handle_spec_run(args)
        when "flaky_check" then handle_flaky_check(args)
        when "routes" then handle_routes(args)
        when "model" then handle_model(args)
        when "controller" then handle_controller(args)
        else
          raise Coatepec::Error.new(:internal_error, "Unknown command #{command}")
        end
      end

      def handle_spec_run(args)
        Spec::Runner.new(@project_root, rails_runtime: @runtime).run(**args.transform_keys(&:to_sym))
      end

      def handle_flaky_check(args)
        Spec::FlakyChecker.new(@project_root, rails_runtime: @runtime).call(**args.transform_keys(&:to_sym))
      end

      def handle_routes(args)
        Introspection::Routes.new(**args.transform_keys(&:to_sym)).call
      end

      def handle_model(args)
        a = args.transform_keys(&:to_sym)
        Introspection::Model.new(a[:name], fields: a[:fields]).call
      end

      def handle_controller(args)
        Introspection::Controller.new(args.transform_keys(&:to_sym)[:name]).call
      end
    end
  end
end
