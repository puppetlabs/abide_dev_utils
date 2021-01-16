#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/abide_dev_utils'

AbideDevUtils::XCCDF.to_hiera('/Users/heston.snodgrass/Documents/CIS/benchmarks/CIS_CentOS_Linux_7_Benchmark_v3.0.0-xccdf.xml')
