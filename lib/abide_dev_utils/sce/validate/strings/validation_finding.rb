# frozen_string_literal: true

module AbideDevUtils
  module Sce
    module Validate
      module Strings
        # Represents a validation finding (warning or error)
        class ValidationFinding
          attr_reader :type, :title, :data

          def initialize(type, title, data)
            raise ArgumentError, 'type must be :error or :warning' unless %i[error warning].include?(type)

            @type = type.to_sym
            @title = title.to_sym
            @data = data
          end

          def to_s
            "#{@type}: #{@title}: #{@data}"
          end

          def to_hash
            { type: @type, title: @title, data: @data }
          end
          alias to_h to_hash
        end
      end
    end
  end
end
