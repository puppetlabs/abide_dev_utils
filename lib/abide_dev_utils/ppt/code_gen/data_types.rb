# frozen_string_literal: true

require 'puppet'

module AbideDevUtils
  module Ppt
    module CodeGen
      module DataTypes
        def infer_data_type(data)
          Puppet::Pops::Types::TypeCalculator.infer(data).to_s
        end

        # Displays a Puppet type value as a string
        def display_value(val)
          if val.is_a?(Puppet::Pops::Model::LiteralUndef)
            'undef'
          elsif val.respond_to?(:value)
            display_value(val.value)
          elsif val.respond_to?(:cased_value)
            display_value(val.cased_value)
          else
            val
          end
        end

        # Displays a Puppet type expression (type signature) as a string
        # @param param [Puppet::Pops::Model::Parameter] AST Parameter node of a parsed Puppet manifest
        def display_type_expr(param)
          te = param.respond_to?(:type_expr) ? param.type_expr : param
          if te.respond_to? :left_expr
            display_type_expr_with_left_expr(te)
          elsif te.respond_to? :entries
            display_type_expr_with_entries(te)
          elsif te.respond_to? :cased_value
            te.cased_value
          elsif te.respond_to? :value
            te.value
          end
        end

        # Used by #display_type_expr
        def display_type_expr_with_left_expr(te)
          cased = nil
          keys = nil
          cased = te.left_expr.cased_value if te.left_expr.respond_to? :cased_value
          keys = te.keys.map { |x| display_type_expr(x) }.to_s if te.respond_to? :keys
          keys.tr!('"', '') unless cased == 'Enum'
          "#{cased}#{keys}"
        end

        # Used by #display_type_expr
        def display_type_expr_with_entries(te)
          te.entries.each_with_object({}) do |x, hsh|
            key = nil
            val = nil
            key = display_value(x.key) if x.respond_to? :key
            val = display_type_expr(x.value) if x.respond_to? :value
            hsh[key] = val if key
          end
        end
      end
    end
  end
end
