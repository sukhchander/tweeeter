module Tweeter

  class ResponseHandler

    def decode_response(res)
      res
    end

  end

  class JsonResponse < Tweeter::ResponseHandler

    def decode_response(res)
      json_result = JSON.parse(res)
      load_recursive(json_result)
    end

  private

    def load_recursive(value)
      if value.kind_of? Hash
        build_struct(value)
      elsif value.kind_of? Array
        value.map { |v| load_recursive(v) }
      else
        value
      end
    end

    def build_struct(hash)
      struct = TwitterStruct.new
      hash.each { |key,val| struct.send("#{key}=", load_recursive(val)) }
      struct
    end

  end

end