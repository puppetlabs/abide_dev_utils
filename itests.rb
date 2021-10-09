#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'yaml'
require 'abide_dev_utils/comply'
require 'abide_dev_utils/ppt/api'

OS_BENCHMARK_MAP = {
  'centos-7' => 'CIS_CentOS_Linux_7_Benchmark_v3.1.1-xccdf.xml',
  'centos-8' => 'CIS_CentOS_Linux_8_Benchmark_v1.0.1-xccdf.xml',
  'rhel-7' => 'CIS_Red_Hat_Enterprise_Linux_7_Benchmark_v3.1.1-xccdf.xml',
  'rhel-8' => 'CIS_Red_Hat_Enterprise_Linux_8_Benchmark_v1.0.1-xccdf.xml',
  'serv-2016' => 'CIS_Microsoft_Windows_Server_2016_RTM_(Release_1607)_Benchmark_v1.3.0-xccdf.xml',
  'serv-2019' => 'CIS_Microsoft_Windows_Server_2019_Benchmark_v1.2.1-xccdf.xml'
}
EL_PROFILE_1_SERVER = 'xccdf_org.cisecurity.benchmarks_profile_Level_1_-_Server'
WIN_PROFILE_1_MS = 'xccdf_org.cisecurity.benchmarks_profile_Level_1_-_Member_Server'
NIX_SCAN_HASH = {
  'nix-centos-7.c.team-sse.internal' => {
    'benchmark' => OS_BENCHMARK_MAP['centos-7'],
    'profile' => EL_PROFILE_1_SERVER
  },
  'nix-centos-8.c.team-sse.internal' => {
    'benchmark' => OS_BENCHMARK_MAP['centos-8'],
    'profile' => EL_PROFILE_1_SERVER
  },
  'nix-rhel-7.c.team-sse.internal' => {
    'benchmark' => OS_BENCHMARK_MAP['rhel-7'],
    'profile' => EL_PROFILE_1_SERVER
  },
  'nix-rhel-8.c.team-sse.internal' => {
    'benchmark' => OS_BENCHMARK_MAP['rhel-8'],
    'profile' => EL_PROFILE_1_SERVER
  }
}.freeze
WIN_SCAN_HASH = {
  'win-server-2016.c.team-sse.internal' => {
    'benchmark' => OS_BENCHMARK_MAP['serv-2016'],
    'profile' => EL_PROFILE_1_SERVER
  },
  'win-serv-2019.c.team-sse.internal' => {
    'benchmark' => OS_BENCHMARK_MAP['serv-2019'],
    'profile' => WIN_PROFILE_1_MS
  }
}.freeze

scan_hash = ENV['ABIDE_OS'] == 'nix' ? NIX_SCAN_HASH : WIN_SCAN_HASH
node_group_name = ENV['ABIDE_OS'] == 'nix' ? 'CEM Linux Nodes' : 'CEM Windows Nodes'

puts 'Creating client...'
client = AbideDevUtils::Ppt::ApiClient.new(ENV['PUPPET_HOST'], auth_token: ENV['PE_ACCESS_TOKEN'])
puts 'Starting code deploy...'
code_manager_deploy = client.post_codemanager_deploys('environments' => ['production'], 'wait' => true)
raise 'Code manager deployment failed!' unless code_manager_deploy['status'] == 'complete'

puts 'Code deploy successful...'
puts 'Gathering node group ID...'
node_groups = client.get_classifier1_groups
node_group_id = nil
node_groups.each { |x| node_group_id = x['id'] if x['name'] == node_group_name }
raise 'Failed to find requested node group!' if node_group_id.nil?

puts 'Running Puppet on nodes...'
puppet_run = client.post_orchestrator_command_deploy('environment' => 'production', 'scope' => { 'node_group' => node_group_id })
puts "Started job #{puppet_run['job']['name']}..."
timeout = 0
run_complete = false
until run_complete || timeout >= 30
  puts "Waiting on job #{puppet_run['job']['name']} to complete..."
  status = client.get_orchestrator_jobs(puppet_run['job']['name'])
  case status['state']
  when 'failed'
    raise "Job #{puppet_run['job']['name']} finished with failures!"
  when 'finished'
    run_complete = true
    break
  else
    timeout += 1
    sleep(10)
  end
end
raise 'Job timed out waiting for completion' unless run_complete

puts 'Starting node scans...'
scan_job = client.post_orchestrator_command_task(
  'environment' => 'production',
  'task' => 'comply::ciscat_scan',
  'params' => {
    'comply_port' => '443',
    'comply_server' => ENV['COMPLY_FQDN'],
    'ssl_verify_mode' => 'none',
    'scan_type' => 'desired',
    'scan_hash' => JSON.generate(scan_hash)
  },
  'scope' => {
    'node_group' => node_group_id
  }
)
puts "Started scan #{scan_job['job']['name']}..."
timeout = 0
scan_complete = false
until scan_complete || timeout >= 30
  puts "Waiting on scan #{scan_job['job']['name']} to complete..."
  status = client.get_orchestrator_jobs(scan_job['job']['name'])
  case status['state']
  when 'failed'
    raise "Task #{scan_job['job']['name']} finished with failures!"
  when 'finished'
    scan_complete = true
    break
  else
    timeout += 1
    sleep(10)
  end
end
raise 'Job timed out waiting for completion' unless scan_complete

puts 'Collecting scan report from Comply...'
onlylist = scan_hash.keys
scan_report = AbideDevUtils::Comply.build_report("https://#{ENV['COMPLY_FQDN']}", ENV['COMPLY_PASSWORD'], nil, onlylist: onlylist)
puts 'Saving report to nix_report.yaml...'
File.open('nix_report.yaml', 'w') { |f| f.write(scan_report.to_yaml) }

puts 'Comparing current report to last report...'
opts = {
  report_name: 'nix_report.yaml',
  remote_storage: 'gcloud',
  upload: true
}
result = AbideDevUtils::Comply.compare_reports(File.expand_path('./nix_report.yaml'), 'nix_report.yaml', opts)
if result
  puts 'Success!'
  exit(0)
else
  puts 'Failure!'
  exit(1)
end
