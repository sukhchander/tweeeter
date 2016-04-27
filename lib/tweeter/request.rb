module Tweeter

  class Request

    attr_accessor :client, :path, :method, :api, :ssl, :params

    def initialize(client, api=:rest, ssl=true)
      @client = client
      @api = api
      @ssl = ssl
      @path = ''
    end

    def scheme
      @ssl ? 'https' : 'http'
    end

    def host
      @client.api_hosts[api]
    end

    def url
      "#{scheme}://#{host}#{@path}"
    end

    def params
      @params ||= {}
    end

    def <<(path)
      @path << path
    end

    def path?
      @path.length > 0
    end

  end

end