module Tweeter

  class Headers

    include Enumerable

    def initialize
      @data = {}
    end

    def [](name)
      res = @data[name.downcase.to_sym]
      res ? res.join(",") : nil
    end

    def []=(name,value)
      @data[name.downcase.to_sym] = [value]
    end

    def add(name,value)
      res = (@data[name.downcase.to_sym] ||= [])
      res << value
    end

    def add_all(name,values)
      res = (@data[name.downcase.to_sym] ||= [])
      res.push(*values)
    end

    def each
      @data.each do |name,value|
        yield(name.to_s,value.join(","))
      end
    end

    def size
      @data.size
    end

  end

end