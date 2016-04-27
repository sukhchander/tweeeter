module Tweeter

  class TwitterStruct < OpenStruct
    attr_accessor :id
  end

  class TwitterError < StandardError

    attr_accessor :method, :request_uri, :status, :response_body, :response_obj

    def initialize(method, request_uri, status=nil, response_body=nil, msg=nil)
      @method = method
      @request_uri = request_uri
      @status = status
      @response_body = response_body
      message = [@method, @request_uri, @status, @response_body].join(' - ')
      super(msg || message)
    end

  end

  class Client

    VALID_FORMATS     = [:json]
    VALID_HTTP_CODES  = [200]

    TWITTER_API_HOSTS = {
      v1: 'api.twitter.com/1',
      v1_1: 'api.twitter.com/1.1'
    }
    TWITTER_API_HOSTS[:rest] = TWITTER_API_HOSTS[:v1]
    DEFAULT_API_HOST = :v1_1

    DEFAULT_RESPONSE_HEADERS = [
      'x-rate-limit-limit',
      'x-rate-limit-remaining',
      'x-rate-limit-reset'
    ]

    TWITTER_OAUTH_SPEC = {
      request_token_path: '/oauth/request_token',
      access_token_path: '/oauth/access_token',
      authorize_path: '/oauth/authorize'
    }

    attr_accessor :auth, :handlers, :default_format, :headers, :ssl, :api,
      :transport, :request, :api_hosts, :auto_append_ids, :auto_append_format,
      :response_headers, :response, :valid_http_codes

    def initialize(options={})
      self.ssl = options[:ssl] || true
      self.api = options[:api] || DEFAULT_API_HOST
      self.api_hosts = TWITTER_API_HOSTS.clone
      self.transport = Tweeter::Transport.new
      self.handlers = {json: Tweeter::JsonResponse.new }
      self.default_format = options[:default_format] || :json
      self.auto_append_format = options[:auto_append_format] == false ? false : true
      self.headers = options[:headers]
      self.auto_append_ids = options[:auto_append_ids] == false ? false : true
      self.response_headers = options[:response_headers] || DEFAULT_RESPONSE_HEADERS.clone
      self.valid_http_codes = options[:valid_http_codes] || VALID_HTTP_CODES.clone
      self.auth = {type: :oauth}.merge(TWITTER_OAUTH_SPEC).merge(options[:auth]||{})
    end

    def method_missing(name,*args,&block)
      if block_given?
        return request_with_http_method_block(name,&block)
      end
      append(name,*args)
    end

    def [](api_name)
      request.api = api_name
      self
    end

    def clear
      self.request = nil
    end

    def append(name,*args)
      name = name.to_s.to_sym
      self.request.params = args.first
      if format_invocation?(name)
        return call_with_format(name)
      end
      if name.to_s =~ /^(.*)(!|\?)$/
        name = $1.to_sym
        self.request.method ||= ($2 == '!' ? :post : :get)
        if format_invocation?(name)
          return call_with_format(name)
        else
          self.request << "/#{$1}"
          return call_with_format(self.default_format)
        end
      end
      self.request << "/#{name}"
      self
    end
    alias_method :_, :append

  protected

    def call_with_format(format)
      if auto_append_ids
        id = request.params.delete(:id)
        request << "/#{id}" if id
      end
      request << ".#{format}" if auto_append_format
      res = send_request
      process_response(format,res)
    ensure
      clear
    end

    def send_request
      begin
        http_method = request.params.delete(:__method) || request.method || :get
        @response = transport.request(
          http_method,
          request.url,
          auth: auth,
          headers: headers,
          params: request.params,
          response_headers: response_headers
        )
      rescue => e
        raise TwitterError.new(request.method, request.url, nil, nil, "Unexpected failure making request: #{e}")
      end
    end

    def process_response(format,res)
      fmt_handler = handler(format)
      begin
        if self.valid_http_codes.include?(res.status)
          fmt_handler.decode_response(res.body)
        else
          handle_error_response(res,fmt_handler)
        end
      rescue TwitterError => e
        raise e
      rescue => e
        raise TwitterError.new(res.method,res.request_uri,res.status,res.body,"Unable to decode response: #{e}")
      end
    end

    def request
      @request ||= Tweeter::Request.new(self,api,ssl)
    end

    def handler(format)
      handlers[format] || handlers[:unknown]
    end

    def handle_error_response(res,handler)
      err = TwitterError.new(res.method,res.request_uri,res.status,res.body)
      err.response_obj = handler.decode_response(err.response_body)
      raise err
    end

    def format_invocation?(name)
      self.request.path? && VALID_FORMATS.include?(name)
    end

    def pending_request?
      !@request.nil?
    end

    def request_with_http_method_block(method,&block)
      request.method = method
      response = instance_eval(&block)
      if pending_request?
        call_with_format(self.default_format)
      else
        response
      end
    end

  end
end