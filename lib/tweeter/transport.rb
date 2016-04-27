module Tweeter

  class Transport

    attr_accessor :debug, :proxy, :cert_file

    CRLF = "\r\n"

    def req_class(method)
      Net::HTTP.const_get(method.to_s.capitalize)
    end

    def request(method, url, options={})
      params = stringify_params(options[:params])
      url << query_string(params) if method == :get && params
      uri = URI.parse(url)
      begin
        execute_request(method, uri, options)
      rescue Timeout::Error
        raise "Timeout::Error #{method.upcase} #{uri}"
      end
    end

    def execute_request(method, url, options={})
      conn = http_class.new(url.host, url.port)
      conn.use_ssl = (url.scheme == 'https')
      configure_ssl(conn) if conn.use_ssl?
      conn.start do |http|
        req = req_class(method).new(url.request_uri)
        add_headers(req, options[:headers])
        add_form_data(req, options[:params])
        add_oauth(http, req, options[:auth])
        res = http.request(req)
        if res.code.to_s =~ /^3\d\d$/ && res['location']
          uri = URI.parse(res['location'])
          execute_request(method, uri, options)
        else
          headers = filter_headers(options[:response_headers], res)
          Tweeter::Response.new(method, url, res.code.to_i, res.body, headers)
        end
      end
    end

    def query_string(params)
      query = case params
        when Hash then params.map{|key,value| url_encode_param(key,value) }.join("&")
        else url_encode(params.to_s)
      end
      query = "?#{query}" if !(query == nil || query.length == 0) && query[0,1] != '?'
      query
    end

  private

    def stringify_params(params)
      return nil unless params
      params.inject({}) do |hash, pair|
        key, value = pair
        hash[key] = value
        hash
      end
    end

    def url_encode(value)
      CGI.escape(value.to_s)
    end

    def url_encode_param(key,value)
      "#{url_encode(key)}=#{url_encode(value)}"
    end

    def add_headers(req,headers)
      headers.each { |header, value| req[header] = value } if headers
    end

    def add_form_data(req,params)
      req.set_form_data(params) if request_body_permitted?(req) && params
    end

    def add_oauth(conn,req,auth)
      options = auth.reject do |key,value|
        [:type, :consumer_key, :consumer_secret, :token, :token_secret].include?(key)
      end
      options[:site] = oauth_site(conn,req) unless options.has_key?(:site)
      consumer = OAuth::Consumer.new(auth[:consumer_key],auth[:consumer_secret],options)
      access_token = OAuth::AccessToken.new(consumer,auth[:token],auth[:token_secret])
      consumer.sign!(req,access_token)
    end

    def oauth_site(conn,req)
      "#{(conn.use_ssl? ? "https" : "http")}://#{conn.address}"
    end

    def dump_request(req)
      dump_headers(req)
    end

    def dump_response(res)
      dump_headers(res)
    end

    def dump_headers(msg)
      msg.each_header { |key, value| puts "\t#{key}=#{value}" }
    end

    def filter_headers(headers, res)
      filtered = Tweeter::Headers.new
      headers.each { |h| filtered.add(h, res[h]) }
      filtered
    end

    def http_class
      if proxy
        if proxy.kind_of?(Proc)
          proxy.call(self)
        else
          proxy
        end
      else
        Net::HTTP
      end
    end

    def configure_ssl(conn)
      conn.ca_file = OpenSSL::X509::DEFAULT_CERT_FILE
      conn.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end

    def request_body_permitted?(req)
      req.request_body_permitted? || req.kind_of?(Net::HTTP::Delete)
    end

  end

end