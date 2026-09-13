# frozen_string_literal: true

module Coatepec
  module Introspection
    # Caps the array-valued entries of a sanitized validator options hash (see SafeOptions) for rails_model output:
    # 249 country codes just say "allow-list", and the count plus flag beside a cut list keep it self-describing.
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
