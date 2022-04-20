#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'pry'
require 'abide_dev_utils/xccdf/diff/benchmark'

xml_file1 = File.expand_path(ARGV[0])
xml_file2 = File.expand_path(ARGV[1])
legacy_config = ARGV.length > 2 ? YAML.load_file(File.expand_path(ARGV[2])) : nil

def convert_legacy_config(config, num_title_diff, key_format: :hiera_num)
  nt_diff = num_title_diff.diff(key: :number)
  updated_config = config['config']['control_configs'].each_with_object({}) do |(key, value), h|
    next if value.nil?

    diff_key = key.to_s.gsub(/^c/, '').tr('_', '.') if key_format == :hiera_num
    if nt_diff.key?(diff_key)
      if nt_diff[diff_key][0][:diff] == :number
        new_key = "c#{nt_diff[diff_key][0][:other_number].to_s.tr('.', '_')}"
        h[new_key] = value
        puts "Converted #{key} to #{new_key}"
      elsif nt_diff[diff_key][0][:diff] == :title

        h[key] = value
      end
    else
      h[key] = value
    end
  end
  { 'config' => { 'control_configs' => updated_config } }.to_yaml
end

start_time = Time.now

bm_diff = AbideDevUtils::XCCDF::Diff::BenchmarkDiff.new(xml_file1, xml_file2)
self_nc_count, other_nc_count = bm_diff.numbered_children_counts
puts "Benchmark numbered children count: #{self_nc_count}"
puts "Other benchmark numbered children count: #{other_nc_count}"
puts "Rule count difference: #{bm_diff.numbered_children_count_diff}"
num_diff = bm_diff.number_title_diff
binding.pry if legacy_config.nil?
File.open('/tmp/legacy_converted.yaml', 'w') do |f|
  converted = convert_legacy_config(legacy_config, num_diff)
  f.write(converted)
end

puts "Computation time: #{Time.now - start_time}"
