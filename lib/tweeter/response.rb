module Tweeter

  class Response

    attr_accessor :method, :request_uri, :status, :body, :headers

    def initialize(method, request_uri, status, body, headers)
      @method = method
      @request_uri = request_uri
      @status = status
      @headers = headers
      @body = body
    end

  end

end