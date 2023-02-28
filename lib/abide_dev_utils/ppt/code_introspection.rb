# frozen_string_literal: true

require 'puppet_pal'
require_relative 'code_gen/data_types'

module AbideDevUtils
  module Ppt
    module CodeIntrospection
      class Manifest
        attr_reader :manifest_file

        def initialize(manifest_file)
          @compiler = Puppet::Pal::Compiler.new(nil)
          @manifest_file = File.expand_path(manifest_file)
          raise ArgumentError, "File #{@manifest_file} is not a file" unless File.file?(@manifest_file)
        end

        def ast
          @ast ||= non_validating_parse_file(manifest_file)
        end

        def declaration
          @declaration ||= Declaration.new(ast)
        end

        private

        # This method gets around the normal validation performed by the regular
        # Puppet::Pal::Compiler#parse_file method. This is necessary because, with
        # validation enabled, the parser will raise errors during parsing if the
        # file contains any calls to Facter. This is due to facter being disallowed
        # in Puppet when evaluating the code in a scripting context instead of catalog
        # compilation, which is what we are doing here.
        def non_validating_parse_file(file)
          @compiler.send(:internal_evaluator).parser.parse_file(file)&.model
        end
      end

      class Declaration
        include AbideDevUtils::Ppt::CodeGen::DataTypes
        attr_reader :ast

        def initialize(ast)
          @ast = ast.definitions.first
        end

        def parameters?
          ast.respond_to? :parameters
        end

        def parameters
          return unless parameters?

          @parameters ||= ast.parameters.map { |p| Parameter.new(p) }
        end
      end

      class Parameter
        include AbideDevUtils::Ppt::CodeGen::DataTypes
        attr_reader :ast

        def initialize(param_ast)
          @ast = param_ast
        end

        def to_a(raw: false)
          [type_expr(raw: raw), name(raw: raw), value(raw: raw)]
        end

        def to_h(raw: false)
          {
            type_expr: type_expr(raw: raw),
            name: name(raw: raw),
            value: value(raw: raw),
          }
        end

        def to_s(raw: false)
          stra = [type_expr(raw: raw), name(raw: raw)]
          stra << '=' if value? && !raw
          stra << value(raw: raw)
          stra.compact.join(' ')
        end

        def name(raw: false)
          return ast.name if raw

          "$#{ast.name}"
        end

        def value?
          ast.respond_to? :value
        end

        def value(raw: false)
          return unless value?
          return ast.value if raw

          display_value(ast)
        end

        def type_expr?
          ast.respond_to? :type_expr
        end

        def type_expr(raw: false)
          return unless type_expr?
          return ast.type_expr if raw

          display_type_expr(ast)
        end
      end
    end
  end
end
