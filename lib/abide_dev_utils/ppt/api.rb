# frozen_string_literal: true

require 'io/console'
require 'json'
require 'net/http'
require 'openssl'

module AbideDevUtils
  module Ppt
    class ApiClient
      attr_reader :hostname, :custom_ports
      attr_writer :auth_token, :tls_cert_verify
      attr_accessor :content_type

      CT_JSON = 'application/json'
      API_DEFS = {
        codemanager: {
          port: 8170,
          version: 'v1',
          base: 'code-manager',
          paths: [
            {
              path: 'deploys',
              verbs: %w[post],
              x_auth: true
            }
          ]
        },
        classifier1: {
          port: 4433,
          version: 'v1',
          base: 'classifier-api',
          paths: [
            {
              path: 'groups',
              verbs: %w[get post],
              x_auth: true
            }
          ]
        },
        orchestrator: {
          port: 8143,
          version: 'v1',
          base: 'orchestrator',
          paths: [
            {
              path: 'command/deploy',
              verbs: %w[post],
              x_auth: true
            },
            {
              path: 'command/task',
              verbs: %w[post],
              x_auth: true
            },
            {
              path: 'jobs',
              verbs: %w[get],
              x_auth: true
            }
          ]
        }
      }.freeze

      def initialize(hostname, auth_token: nil, content_type: CT_JSON, custom_ports: {}, verbose: false)
        @hostname = hostname
        @auth_token = auth_token
        @content_type = content_type
        @custom_ports = custom_ports
        @verbose = verbose
        define_api_methods
      end

      def login(username, password: nil, lifetime: '1h', label: nil)
        label = "AbideDevUtils token for #{username} - lifetime #{lifetime}" if label.nil?
        password = IO.console.getpass 'Password: ' if password.nil?
        data = {
          'login' => username,
          'password' => password,
          'lifetime' => lifetime,
          'label' => label
        }
        uri = URI("https://#{@hostname}:4433/rbac-api/v1/auth/token")
        result = http_request(uri, post_request(uri, x_auth: false, **data), json_out: true)
        @auth_token = result['token']
        log_verbose("Successfully logged in? #{auth_token?}")
        auth_token?
      end

      def auth_token?
        defined?(@auth_token) && !@auth_token.nil? && !@auth_token.empty?
      end

      def tls_cert_verify
        @tls_cert_verify = defined?(@tls_cert_verify) ? @tls_cert_verify : false
      end

      def verbose?
        @verbose
      end

      def no_verbose
        @verbose = false
      end

      def verbose!
        @verbose = true
      end

      private

      def define_api_methods
        api_method_data.each do |meth, data|
          case meth
          when /^get_.*/
            self.class.define_method(meth) do |*args, **kwargs|
              uri = args.empty? ? data[:uri] : URI("#{data[:uri]}/#{args.join('/')}")
              req = get_request(uri, x_auth: data[:x_auth], **kwargs)
              http_request(data[:uri], req, json_out: true)
            end
          when /^post_.*/
            self.class.define_method(meth) do |*args, **kwargs|
              uri = args.empty? ? data[:uri] : URI("#{data[:uri]}/#{args.join('/')}")
              req = post_request(uri, x_auth: data[:x_auth], **kwargs)
              http_request(data[:uri], req, json_out: true)
            end
          else
            raise "Cannot define method for #{meth}"
          end
        end
      end

      def api_method_data
        method_data = {}
        API_DEFS.each do |key, val|
          val[:paths].each do |path|
            method_names = api_method_names(key, path)
            method_names.each do |name|
              method_data[name] = {
                uri: api_method_uri(val[:port], val[:base], val[:version], path[:path]),
                x_auth: path[:x_auth]
              }
            end
          end
        end
        method_data
      end

      def api_method_names(api_name, path)
        path[:verbs].each_with_object([]) do |verb, ary|
          path_str = path[:path].split('/').join('_')
          ary << [verb, api_name.to_s, path_str].join('_')
        end
      end

      def api_method_uri(port, base, version, path)
        URI("https://#{@hostname}:#{port}/#{base}/#{version}/#{path}")
      end

      def get_request(uri, x_auth: true, **qparams)
        log_verbose('New GET request:')
        log_verbose("request_qparams?: #{!qparams.empty?}")
        uri.query = URI.encode_www_form(qparams) unless qparams.empty?
        headers = init_headers(x_auth: x_auth)
        log_verbose("request_headers: #{redact_headers(headers)}")
        Net::HTTP::Get.new(uri, headers)
      end

      def post_request(uri, x_auth: true, **data)
        log_verbose('New POST request:')
        log_verbose("request_data?: #{!data.empty?}")
        headers = init_headers(x_auth: x_auth)
        log_verbose("request_headers: #{redact_headers(headers)}")
        req = Net::HTTP::Post.new(uri, headers)
        req.body = data.to_json unless data.empty?
        req
      end

      def init_headers(x_auth: true)
        headers = { 'Content-Type' => @content_type }
        return headers unless x_auth

        raise 'Auth token not set!' unless auth_token?

        headers['X-Authentication'] = @auth_token
        headers
      end

      def http_request(uri, req, json_out: true)
        result = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, verify_mode: tls_verify_mode) do |http|
          log_verbose("use_ssl: true, verify_mode: #{tls_verify_mode}")
          http.request(req)
        end
        case result.code
        when '200', '201', '202'
          json_out ? JSON.parse(result.body) : result
        else
          jbody = JSON.parse(result.body)
          log_verbose("HTTP #{result.code} #{jbody['kind']} #{jbody['msg']} #{jbody['details']} #{uri}")
          raise "HTTP #{result.code} #{jbody['kind']} #{jbody['msg']} #{jbody['details']} #{uri}"
        end
      end

      def log_verbose(msg)
        puts msg if @verbose
      end

      def redact_headers(headers)
        r_headers = headers.dup
        r_headers['X-Authentication'] = 'XXXXX' if r_headers.key?('X-Authentication')
        r_headers
      end

      def tls_verify_mode
        tls_cert_verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      end
    end
  end
end
