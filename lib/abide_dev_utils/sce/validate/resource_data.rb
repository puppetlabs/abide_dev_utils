# frozen_string_literal: true

require 'abide_dev_utils/ppt'
require 'abide_dev_utils/sce/benchmark'

module AbideDevUtils
  module Sce
    module Validate
      # Validation methods for resource data
      module ResourceData
        class ControlsWithoutMapsError < StandardError; end

        def self.controls_without_maps(module_dir = Dir.pwd)
          pupmod = AbideDevUtils::Ppt::PuppetModule.new(module_dir)
          benchmarks = AbideDevUtils::Sce::Benchmark.benchmarks_from_puppet_module(pupmod)
          without_maps = benchmarks.each_with_object({}) do |benchmark, hsh|
            puts "Validating #{benchmark.title}..."
            hsh[benchmark.title] = benchmark.controls.each_with_object([]) do |ctrl, no_maps|
              no_maps << ctrl.id unless ctrl.valid_maps?
            end
          end
          err = ['Found controls in resource data without maps.']
          without_maps.each do |key, val|
            next if val.empty?

            err << val.unshift("#{key}:").join("\n  ")
          end
          raise ControlsWithoutMapsError, err.join("\n") unless without_maps.values.all?(&:empty?)
        end
      end
    end
  end
end
