require File.dirname(__FILE__) + '/test_helper'

class HandlerTest < Test::Unit::TestCase

  def test_json_handler_parses_basic_attributes
    h = Tweeter::JsonResponse.new
    body = '{"id":12345,"screen_name":"User1"}'
    value = h.decode_response(body)
    assert_equal(12345,value.id,"Id element should be treated as an attribute and be returned as a Fixnum")
    assert_equal("User1",value.screen_name,"screen_name element should be treated as an attribute")
  end

  def test_json_handler_parses_complex_attributes
    h = Tweeter::JsonResponse.new
    body = '{"id":12345,"screen_name":"User1","statuses":['
    1.upto(10) do |i|
      user_id = i+5000
      body << ',' unless i == 1
      body << %Q{{"id":#{i},"text":"Status from user #{user_id}", "user":{"id":#{user_id},"screen_name":"User #{user_id}"}}}
    end
    body << ']}'
    value = h.decode_response(body)
    assert_equal(12345,value.id,"Id element should be treated as an attribute and be returned as a Fixnum")
    assert_equal("User1",value.screen_name,"screen_name element should be treated as an attribute")
    assert_equal(Array,value.statuses.class,"statuses attribute should be an array")
    1.upto(10) do |i|
      assert_equal(i,value.statuses[i-1].id,"array should contain status with id #{i} at index #{i-1}")
      assert_equal(i+5000,value.statuses[i-1].user.id,"status at index #{i-1} should contain user with id #{i+5000}")
    end
  end

end