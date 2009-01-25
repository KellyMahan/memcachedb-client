module Continuum
  POINTS_PER_SERVER = 160 # this is the default in libmemcached

  begin
    require 'binary_search' # try to load native extension
  rescue LoadError => e
    puts "Unable to load fast binary search, falling back to pure Ruby: #{e.message}"

    # slow but pure ruby version
    # Find the closest index in Continuum with value <= the given value
    def self.binary_search(ary, value, &block)
      upper = ary.size - 1
      lower = 0
      idx = 0

      while(lower <= upper) do
        idx = (lower + upper) / 2
        comp = ary[idx].value <=> value
 
        if comp == 0
          return idx
        elsif comp > 0
          upper = idx - 1
        else
          lower = idx + 1
        end
      end
      return upper
    end
  end


  class Entry
    attr_reader :value
    attr_reader :server

    def initialize(val, srv)
      @value = val
      @server = srv
    end

    def inspect
      "<#{value}, #{server.host}:#{server.port}>"
    end
  end
end
