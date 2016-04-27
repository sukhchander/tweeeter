require File.dirname(__FILE__) + '/test_helper'

class ClientTest < Test::Unit::TestCase

  class Net::HTTP

    class << self
      attr_accessor :response, :request, :last_instance, :responder
    end

    def connect
    end

    def request(req)
      self.class.last_instance = self
      if self.class.responder
        self.class.responder.call(self,req)
      else
        self.class.request = req
        self.class.response
      end
    end

  end

  class MockProxy < Net::HTTP

    class << self
      attr_accessor :started
      [:response,:request,:last_instance,:responder].each do |m|
        class_eval "
          def #{m}; Net::HTTP.#{m}; end
          def #{m}=(val); Net::HTTP.#{m} = val; end
        "
      end
    end

    def start
      self.class.started = true
      super
    end

  end

  class MockResponse < Net::HTTPResponse

    attr_accessor :code, :body

    def initialize(code, body, headers={})
      super
      self.code = code
      self.body = body
      headers.each { |name, value| self[name] = value }
    end

  end

  class MockTransport < Tweeter::Transport

    attr_accessor :status, :body, :method, :url, :options

    def initialize(status,body,headers={})
      Net::HTTP.response = MockResponse.new(status,body,headers)
    end

    def request(method, string_url, options)
      self.method = method
      self.url = URI.parse(string_url)
      self.options = options
      super(method,string_url,options)
    end

  end

  class TestHandler < Tweeter::ResponseHandler

    attr_accessor :decode_value

    def initialize(value)
      self.decode_value = value
    end

    def decode_response(body)
      decode_value
    end

  end

  def test_redirects
    redirects = 2 #Check that we can follow 2 redirects before getting to original request
    req_count = 0
    responder = Proc.new do |inst, req|
      req_count += 1
      #Store the original request
      if req_count == 1
        inst.class.request = req
      else
        assert_equal("/somewhere_else#{req_count-1}.json",req.path)
      end
      if req_count <= redirects
        MockResponse.new(302,"You are being redirected",'location'=>"http://twitter.com/somewhere_else#{req_count}.json")
      else
        inst.class.response
      end
    end
    with_http_responder(responder) do
      test_simple_get_request
    end
    assert_equal(redirects+1,req_count)
  end

  def test_simple_get_request
    client = new_client(200,'{"id":12345,"screen_name":"twitterapi"}')
    value = client.users.show.json? screen_name: 'twitterapi'
    assert_equal(:get,client.transport.method)
    assert_equal('https',client.transport.url.scheme)
    assert_equal('api.twitter.com',client.transport.url.host)
    assert_equal('/1.1/users/show.json',client.transport.url.path)
    assert_equal('twitterapi',client.transport.options[:params][:screen_name])
    assert_equal('screen_name=twitterapi',Net::HTTP.request.path.split(/\?/)[1])
    assert_equal(12345,value.id)
  end

  def test_simple_post_request_with_oauth
    client = Tweeter::Client.new(auth: {type: :oauth,consumer_key: '12345',consumer_secret: 'abc',token: 'wxyz',token_secret: '98765'})
    test_simple_post(client) do
      auth = Net::HTTP.request['Authorization']
      assert_match(/OAuth/i,auth,"Request should include Authorization header for OAuth")
      assert_match(/oauth_consumer_key="12345"/,auth,"Auth header should include consumer key")
      assert_match(/oauth_token="wxyz"/,auth,"Auth header should include token")
      assert_match(/oauth_signature_method="HMAC-SHA1"/,auth,"Auth header should include HMAC-SHA1 signature method as that's what Twitter supports")
    end
  end

  def test_ssl
    client = new_client(200,'[{"id":1,"text":"test 1"}]',ssl: true)
    client.statuses.public_timeline?
    assert_equal("https",client.transport.url.scheme)
    assert(Net::HTTP.last_instance.use_ssl?,'Net::HTTP instance should be set to use SSL')
  end

  def test_ssl_with_cert_file
    client = new_client(200,'[{"id":1,"text":"test 1"}]',ssl: true)
    client.statuses.public_timeline?
    assert_equal(OpenSSL::SSL::VERIFY_PEER,Net::HTTP.last_instance.verify_mode,'Net::HTTP instance should use OpenSSL::SSL::VERIFY_PEER mode')
  end

  def test_default_format
    client = new_client(200,'[{"id":1,"text":"test 1"}]',default_format: :json)
    client.statuses.public_timeline?
    assert_match(/\.json$/,client.transport.url.path)
  end

  def test_headers
    client = new_client(200,'[{"id":1,"text":"test 1"}]',headers: {'X-Test-Header'=>'Header Value'})
    client.statuses.public_timeline?
    assert_equal('Header Value',Net::HTTP.request['X-Test-Header'],"Custom X-Test-Header header should have been set")
  end

  def test_default_response_headers
    client = new_client(200, '[{"id":1,"text":"test 1"}]')
    # Load up some other headers in the response
    Tweeter::Client::DEFAULT_RESPONSE_HEADERS.each_with_index do |header,i|
      Net::HTTP.response[header] = "value#{i}"
    end
    client.statuses.public_timeline?
    headers = client.response.headers
    assert(!headers.nil?)
    assert_equal(Tweeter::Client::DEFAULT_RESPONSE_HEADERS.size, headers.size)
    Tweeter::Client::DEFAULT_RESPONSE_HEADERS.each_with_index do |h,i|
      assert_equal("value#{i}",headers[h])
    end
  end

  def test_custom_response_headers
    response_headers = ['X-Your-Face-Header']
    client = new_client(200, '[{"id":1,"text":"test 1"}]', response_headers: response_headers)

    # Load up some other headers in the response
    Net::HTTP.response["X-Your-Face-Header"] = "asdf"
    Net::HTTP.response["X-Something-Else"] = "foo"

    assert_equal(response_headers,client.response_headers,"Response headers should override defaults")

    client.statuses.public_timeline?
    headers = client.response.headers
    assert(!headers.nil?)
    assert_equal(response_headers.size, headers.size)

    assert_equal("asdf",headers["X-Your-Face-Header"])
    assert(headers["X-Something-Else"].nil?)
  end

  def test_clear
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    client.some.url.that.does.not.exist
    assert_equal('/some/url/that/does/not/exist',client.send(:request).path,"An unexecuted path should be built up")
    client.clear
    assert_equal('',client.send(:request).path,"The path should be cleared")
  end

  def test_simple_http_method_block
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    client.delete { direct_messages.destroy id: 1, other: 'value' }
    assert_equal(:delete,client.transport.method, "delete block should use delete method")
    assert_equal("/1.1/direct_messages/destroy/1.json",Net::HTTP.request.path)
    assert_equal('value',client.transport.options[:params][:other])
    client = new_client(200,'{"id":54321,"screen_name":"twitterapi"}')
    value = client.get { users.show.json? screen_name: 'twitterapi' }
    assert_equal(:get,client.transport.method)
    assert_equal('https',client.transport.url.scheme)
    assert_equal('api.twitter.com',client.transport.url.host)
    assert_equal('/1.1/users/show.json',client.transport.url.path)
    assert_equal('twitterapi',client.transport.options[:params][:screen_name])
    assert_equal('screen_name=twitterapi',Net::HTTP.request.path.split(/\?/)[1])
    assert_equal(54321,value.id)
  end

  def test_http_method_blocks_choose_right_method
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    client.get { search q: 'test' }
    assert_equal(:get,client.transport.method, "Get block should choose get method")
    client.delete { direct_messages.destroy id: 1 }
    assert_equal(:delete,client.transport.method, "Delete block should choose delete method")
    client.post { direct_messages.destroy id: 1 }
    assert_equal(:post,client.transport.method, "Post block should choose post method")
    client.put { direct_messages id: 1 }
    assert_equal(:put,client.transport.method, "Put block should choose put method")
  end

  def test_http_method_selection_precedence
    client = new_client(200,'[{"id":1,"text":"test 1"}]')
    client.get { search! q: 'test' }
    assert_equal(:get,client.transport.method, "Get block should override method even if post bang is used")
    client.delete { search? q: 'test', __method: :post }
    assert_equal(:post,client.transport.method, "__method: :post should override block setting and method suffix")
  end

  def test_underscore_method_works_with_numbers
    client = new_client(200,'{"id":12345,"screen_name":"twitterapi"}')
    value = client.users.show._(12345).json?
    assert_equal(:get,client.transport.method)
    assert_equal('https',client.transport.url.scheme)
    assert_equal('api.twitter.com',client.transport.url.host)
    assert_equal('/1.1/users/show/12345.json',client.transport.url.path)
    assert_equal(12345,value.id)
  end

  def test_transport_proxy_setting_is_used
    client = new_client(200,'{"id":12345,"screen_name":"twitterapi"}')
    called = false
    call_trans = nil
    client.transport.proxy = Proc.new {|trans| call_trans = trans; called = true; MockProxy }
    client.users.show._(12345).json?
    assert(called,"Proxy proc should be called during request")
    assert(MockProxy.started,"Proxy should have been called")
    assert_equal(client.transport,call_trans,"Proxy should have been called with transport")
    MockProxy.started = false
    client.transport.proxy = MockProxy
    client.users.show._(12345).json?
    assert(MockProxy.started,"Proxy should have been called")
    MockProxy.started = false
    client.transport.proxy = nil
    assert_equal(false,MockProxy.started,"Proxy should not have been called")
  end

  def test_auto_append_ids_is_honored
    client = new_client(200,'{"id":12345,"screen_name":"twitterapi"}')
    client.users.show.json? id: 12345
    assert_equal('/1.1/users/show/12345.json',client.transport.url.path,"Id should be appended by default")
    client.auto_append_ids = false
    client.users.show.json? id: 12345
    assert_equal('/1.1/users/show.json',client.transport.url.path,"Id should not be appended")
    assert_equal(12345,client.transport.options[:params][:id], "Id should be treated as a parameter")
    assert_equal("id=#{12345}",Net::HTTP.request.path.split(/\?/)[1],"id should be part of the query string")
  end

  def test_auto_append_ids_can_be_set_in_constructor
    client = new_client(200,'{"id":12345,"screen_name":"twitterapi"}',auto_append_ids: false)
    client.users.show.json? id: 12345
    assert_equal('/1.1/users/show.json',client.transport.url.path,"Id should not be appended")
    assert_equal(12345,client.transport.options[:params][:id], "Id should be treated as a parameter")
    assert_equal("id=#{12345}",Net::HTTP.request.path.split(/\?/)[1],"id should be part of the query string")
  end

  def test_auto_append_format_is_honored
    client = new_client(200,'{"id":12345,"screen_name":"twitterapi"}')
    client.users.show.twitterapi?
    assert_equal('/1.1/users/show/twitterapi.json',client.transport.url.path,"Format should be appended by default")
    client.auto_append_format = false
    client.users.show.twitterapi?
    assert_equal('/1.1/users/show/twitterapi',client.transport.url.path,"Format should not be appended to the URI")
  end

  def test_auto_append_format_can_be_set_in_constructor
    client = new_client(200,'{"id":12345,"screen_name":"twitterapi"}',auto_append_format: false)
    client.users.show.twitterapi?
    assert_equal('/1.1/users/show/twitterapi',client.transport.url.path,"Format should not be appended to the URI")
  end

  def test_default_api
    client = Tweeter::Client.new
    assert_equal(:v1_1,client.api,":v1_1 should be default api")
  end

  def test_delete_can_send_body_parameters
    client = new_client(200,'{"id":12345,"name":"Test List","members":0}')
    client.delete { some_user.some_list.members? user_id: 12345 }
    assert_equal(:delete,client.transport.method,"Expected delete request")
    assert_equal('https',client.transport.url.scheme,"Expected scheme to be http")
    assert_equal('api.twitter.com',client.transport.url.host,"Expected request to be against twitter.com")
    assert_equal('/1.1/some_user/some_list/members.json',client.transport.url.path)
    assert_match(/user_id=12345/,Net::HTTP.request.body,"Parameters should be form encoded")
  end

  def test_valid_http_codes_causes_error_not_to_raise
    client = new_client(202,'{"id":12345,"screen_name":"twitterapi"}')
    assert_raise(Tweeter::TwitterError) do
      value = client.users.show.json? screen_name: 'twitterapi'
    end
    client = new_client(202,'{"id":12345,"screen_name":"twitterapi"}',valid_http_codes: [200,202])
    assert_nothing_raised do
      value = client.users.show.json? screen_name: 'twitterapi'
    end
  end

private

  def with_http_responder(responder)
    Net::HTTP.responder = responder
    yield
  ensure
    Net::HTTP.responder = nil
  end

  def new_client(response_status, response_body, options={})
    client = Tweeter::Client.new(options)
    client.transport = MockTransport.new(response_status,response_body)
    client
  end

  def test_simple_post(client)
    client.transport = MockTransport.new(200,'{"id":12345,"text":"test status"}')
    value = client.statuses.update! status: 'test status'
    assert_equal(:post,client.transport.method,"Expected post request")
    assert_equal('https',client.transport.url.scheme,"Expected scheme to be https")
    assert_equal('api.twitter.com',client.transport.url.host,"Expected request to be against twitter.com")
    assert_equal('/1.1/statuses/update.json',client.transport.url.path)
    assert_match(/status=test\+status/,Net::HTTP.request.body,"Parameters should be form encoded")
    assert_equal(12345,value.id)
  end

end