module Continuum
  POINTS_PER_SERVER = 160 # this is the default in libmemcached

  class << self

    begin
      require 'inline'
      inline do |builder|
        builder.c <<-EOM
        int binary_search(VALUE ary, unsigned int r) {
            int upper = RARRAY_LEN(ary) - 1;
            int lower = 0;
            int idx = 0;
            ID value = rb_intern("value");

            while (lower <= upper) {
                idx = (lower + upper) / 2;

                VALUE continuumValue = rb_funcall(RARRAY_PTR(ary)[idx], value, 0);
                unsigned int l = NUM2UINT(continuumValue);
                if (l == r) {
                    return idx;
                }
                else if (l > r) {
                    upper = idx - 1;
                }
                else {
                    lower = idx + 1;
                }
            }
            return upper;
        }
        EOM
      end
    rescue Exception => e
      puts "Unable to generate native code, falling back to Ruby: #{e.message}"

      # slow but pure ruby version
      # Find the closest index in Continuum with value <= the given value
      def binary_search(ary, value, &block)
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
