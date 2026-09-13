# frozen_string_literal: true

module Coatepec
  module Introspection
    # Caps the array-valued entries of an already-sanitized validator options
    # hash (see SafeOptions) before it's serialized as rails_model output.
    # An inclusion list of 249 country codes says "validated against an allow-list"; the first few values suffice.
    # The count and flag beside the cut list make it self-describing, so a short list and a cut one never look alike.
    module BoundedOptions
      module_function

      def call(options, max)
        options.each_with_object({}) do |(key, value), bounded|
          bounded[key] = value
          next unless value.is_a?(Array) && value.size > max

          bounded[key] = value.first(max)
          bounded["#{key}_count"] = value.size
          bounded["#{key}_truncated"] = true
        end
      end
    end
  end
end
