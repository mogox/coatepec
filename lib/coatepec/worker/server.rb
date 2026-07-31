# frozen_string_literal: true

module Coatepec
  module Worker
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
        case command
        when "status"
          @runtime.status
        when "spec_run"
          Spec::Runner.new(@project_root).run(**args.transform_keys(&:to_sym))
        else
          raise Coatepec::Error.new(:internal_error, "Unknown command #{command}")
        end
      end
    end
  end
end
