# encoding: utf-8
require 'logger'
require 'stringio'
require 'test/unit'
require 'rubygems'
begin
  gem 'flexmock'
  require 'flexmock/test_unit'
rescue LoadError => e
  puts "Some tests require flexmock, please run `gem install flexmock`"
end

$TESTING = true

require File.dirname(__FILE__) + '/../lib/memcache'

class MemCacheDb

  attr_writer :namespace

end

class FakeSocketDb

  attr_reader :written, :data

  def initialize
    @written = StringIO.new
    @data = StringIO.new
  end

  def write(data)
    @written.write data
  end

  def gets
    @data.gets
  end

  def read(arg)
    @data.read arg
  end

end

class Test::Unit::TestCase
  def requirement(bool, msg)
    if bool
      yield
    else
      puts msg
      assert true
    end
  end
  
  def memcached_running?
    TCPSocket.new('localhost', 11211) rescue false
  end
  
  def xprofile(name, &block)
    a = Time.now
    block.call
    Time.now - a
  end

  def profile(name, &block)
    require 'ruby-prof'
    a = Time.now
    result = RubyProf.profile(&block)
    time = Time.now - a
    printer = RubyProf::GraphHtmlPrinter.new(result)
    File.open("#{name}.html", 'w') do |f|
      printer.print(f, :min_percent=>1)
    end
    time
  end
  
end

class FakeServerDb

  attr_reader :host, :port, :socket, :weight, :multithread, :status

  def initialize(socket = nil)
    @closed = false
    @host = 'example.com'
    @port = 11211
    @socket = socket || FakeSocketDb.new
    @weight = 1
    @multithread = false
    @status = "CONNECTED"
  end

  def close
    # begin
    #   raise "Already closed"
    # rescue => e
    #   puts e.backtrace.join("\n")
    # end
    @closed = true
    @socket = nil
    @status = "NOT CONNECTED"
  end

  def alive?
    # puts "I'm #{@closed ? 'dead' : 'alive'}"
    !@closed
  end

end

class TestMemCacheDb < Test::Unit::TestCase

  def setup
    @cache = MemCacheDb.new 'localhost:1', :namespace => 'my_namespace'
  end

  def test_performance
    requirement(memcached_running?, 'A real memcached server must be running for performance testing') do
      host = Socket.gethostname

      cache = MemCacheDb.new(['localhost:21201',"#{host}:21201"])
      cache.add('a', 1, 120)
      with = xprofile 'get' do
        1000.times do
          cache.get('a')
        end
      end
      puts ''
      puts "1000 gets with socket timeout: #{with} sec"

      cache = MemCacheDb.new(['localhost:21201',"#{host}:21201"], :timeout => nil)
      cache.add('a', 1, 120)
      without = xprofile 'get' do
        1000.times do
          cache.get('a')
        end
      end
      puts "1000 gets without socket timeout: #{without} sec"

      assert without < with
    end
  end

  def test_consistent_hashing
    requirement(self.respond_to?(:flexmock), 'Flexmock is required to run this test') do

      flexmock(MemCacheDb::Server).new_instances.should_receive(:alive?).and_return(true)

      # Setup a continuum of two servers
      @cache.servers = ['mike1', 'mike2', 'mike3']

      keys = []
      1000.times do |idx|
        keys << idx.to_s
      end

      before_continuum = keys.map {|key| @cache.get_server_for_key(key) }

      @cache.servers = ['mike1', 'mike2', 'mike3', 'mike4']

      after_continuum = keys.map {|key| @cache.get_server_for_key(key) }

      same_count = before_continuum.zip(after_continuum).find_all {|a| a[0].host == a[1].host }.size

      # With continuum, we should see about 75% of the keys map to the same server
      # With modulo, we would see about 25%.
      assert same_count > 700
    end
  end
  
  def test_get_multi_with_server_failure
    @cache = MemCacheDb.new 'localhost:1', :namespace => 'my_namespace', :logger => nil #Logger.new(STDOUT)
    s1 = FakeServerDb.new
    s2 = FakeServerDb.new

    # Write two messages to the socket to test failover
    s1.socket.data.write "VALUE my_namespace:a 0 14\r\n\004\b\"\0170123456789\r\nEND\r\n"
    s1.socket.data.rewind
    s2.socket.data.write "bogus response\r\nbogus response\r\n"
    s2.socket.data.rewind

    @cache.servers = [s1, s2]

    assert s1.alive?
    assert s2.alive?
    # a maps to s1, the rest map to s2
    value = @cache.get_multi(['foo', 'bar', 'a', 'b', 'c'])
    assert_equal({'a'=>'0123456789'}, value)
    assert s1.alive?
    assert !s2.alive?
  end

  def test_cache_get_with_failover
    @cache = MemCacheDb.new 'localhost:1', :namespace => 'my_namespace', :logger => nil#Logger.new(STDOUT)
    s1 = FakeServerDb.new
    s2 = FakeServerDb.new

    # Write two messages to the socket to test failover
    s1.socket.data.write "VALUE foo 0 14\r\n\004\b\"\0170123456789\r\n"
    s1.socket.data.rewind
    s2.socket.data.write "bogus response\r\nbogus response\r\n"
    s2.socket.data.rewind

    @cache.instance_variable_set(:@failover, true)
    @cache.servers = [s1, s2]

    assert s1.alive?
    assert s2.alive?
    @cache.get('foo')
    assert s1.alive?
    assert !s2.alive?
  end
  
  def test_cache_get_without_failover
    s1 = FakeServerDb.new
    s2 = FakeServerDb.new
    
    s1.socket.data.write "VALUE foo 0 14\r\n\004\b\"\0170123456789\r\n"
    s1.socket.data.rewind
    s2.socket.data.write "bogus response\r\nbogus response\r\n"
    s2.socket.data.rewind

    @cache.instance_variable_set(:@failover, false)
    @cache.servers = [s1, s2]

    assert s1.alive?
    assert s2.alive?
    e = assert_raise MemCacheDb::MemCacheDbError do
      @cache.get('foo')
    end
    assert s1.alive?
    assert !s2.alive?

    assert_equal "No servers available", e.message
  end

  def test_cache_get
    server = util_setup_fake_server

    assert_equal "\004\b\"\0170123456789",
                 @cache.cache_get(server, 'my_namespace:key')

    assert_equal "get my_namespace:key\r\n",
                 server.socket.written.string
  end

  def test_cache_get_EOF
    server = util_setup_fake_server
    server.socket.data.string = ''

    e = assert_raise IndexError do
      @cache.cache_get server, 'my_namespace:key'
    end

    assert_equal "No connection to server (NOT CONNECTED)", e.message
  end

  def test_cache_get_bad_state
    server = FakeServerDb.new

    # Write two messages to the socket to test failover
    server.socket.data.write "bogus response\r\nbogus response\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    e = assert_raise IndexError do
      @cache.cache_get(server, 'my_namespace:key')
    end

    assert_match /#{Regexp.quote 'No connection to server (NOT CONNECTED)'}/, e.message

    assert !server.alive?
  end

  def test_cache_get_miss
    socket = FakeSocketDb.new
    socket.data.write "END\r\n"
    socket.data.rewind
    server = FakeServerDb.new socket

    assert_equal nil, @cache.cache_get(server, 'my_namespace:key')

    assert_equal "get my_namespace:key\r\n",
                 socket.written.string
  end

  def test_cache_get_multi
    server = util_setup_fake_server
    server.socket.data.write "VALUE foo 0 7\r\n"
    server.socket.data.write "\004\b\"\bfoo\r\n"
    server.socket.data.write "VALUE bar 0 7\r\n"
    server.socket.data.write "\004\b\"\bbar\r\n"
    server.socket.data.write "END\r\n"
    server.socket.data.rewind

    result = @cache.cache_get_multi server, 'foo bar baz'

    assert_equal 2, result.length
    assert_equal "\004\b\"\bfoo", result['foo']
    assert_equal "\004\b\"\bbar", result['bar']
  end

  def test_cache_get_multi_EOF
    server = util_setup_fake_server
    server.socket.data.string = ''

    e = assert_raise IndexError do
      @cache.cache_get_multi server, 'my_namespace:key'
    end

    assert_equal "No connection to server (NOT CONNECTED)", e.message
  end

  def test_cache_get_multi_bad_state
    server = FakeServerDb.new

    # Write two messages to the socket to test failover
    server.socket.data.write "bogus response\r\nbogus response\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    e = assert_raise IndexError do
      @cache.cache_get_multi server, 'my_namespace:key'
    end

    assert_match /#{Regexp.quote 'No connection to server (NOT CONNECTED)'}/, e.message

    assert !server.alive?
  end

  def test_initialize
    cache = MemCacheDb.new :namespace => 'my_namespace', :readonly => true

    assert_equal 'my_namespace', cache.namespace
    assert_equal true, cache.readonly?
    assert_equal true, cache.servers.empty?
  end

  def test_initialize_compatible
    cache = MemCacheDb.new ['localhost:21201', 'localhost:11212'],
            :namespace => 'my_namespace', :readonly => true

    assert_equal 'my_namespace', cache.namespace
    assert_equal true, cache.readonly?
    assert_equal false, cache.servers.empty?
  end

  def test_initialize_compatible_no_hash
    cache = MemCacheDb.new ['localhost:21201', 'localhost:11212']

    assert_equal nil, cache.namespace
    assert_equal false, cache.readonly?
    assert_equal false, cache.servers.empty?
  end

  def test_initialize_compatible_one_server
    cache = MemCacheDb.new 'localhost:21201'

    assert_equal nil, cache.namespace
    assert_equal false, cache.readonly?
    assert_equal false, cache.servers.empty?
  end

  def test_initialize_compatible_bad_arg
    e = assert_raise ArgumentError do
      cache = MemCacheDb.new Object.new
    end

    assert_equal 'first argument must be Array, Hash or String', e.message
  end

  def test_initialize_multiple_servers
    cache = MemCacheDb.new %w[localhost:21201 localhost:11212],
                         :namespace => 'my_namespace', :readonly => true

    assert_equal 'my_namespace', cache.namespace
    assert_equal true, cache.readonly?
    assert_equal false, cache.servers.empty?
    assert !cache.instance_variable_get(:@continuum).empty?
  end

  def test_initialize_too_many_args
    assert_raises ArgumentError do
      MemCacheDb.new 1, 2, 3
    end
  end

  def test_decr
    server = FakeServerDb.new
    server.socket.data.write "5\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    value = @cache.decr 'key'

    assert_equal "decr my_namespace:key 1\r\n",
                 @cache.servers.first.socket.written.string

    assert_equal 5, value
  end

  def test_decr_not_found
    server = FakeServerDb.new
    server.socket.data.write "NOT_FOUND\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    value = @cache.decr 'key'

    assert_equal "decr my_namespace:key 1\r\n",
                 @cache.servers.first.socket.written.string

    assert_equal nil, value
  end

  def test_decr_space_padding
    server = FakeServerDb.new
    server.socket.data.write "5 \r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    value = @cache.decr 'key'

    assert_equal "decr my_namespace:key 1\r\n",
                 @cache.servers.first.socket.written.string

    assert_equal 5, value
  end

  def test_get
    util_setup_fake_server

    value = @cache.get 'key'

    assert_equal "get my_namespace:key\r\n",
                 @cache.servers.first.socket.written.string

    assert_equal '0123456789', value
  end

  def test_get_bad_key
    util_setup_fake_server
    assert_raise ArgumentError do @cache.get 'k y' end

    util_setup_fake_server
    assert_raise ArgumentError do @cache.get 'k' * 250 end
  end

  def test_get_cache_get_IOError
    socket = Object.new
    def socket.write(arg) raise IOError, 'some io error'; end
    server = FakeServerDb.new socket

    @cache.servers = []
    @cache.servers << server

    e = assert_raise MemCacheDb::MemCacheDbError do
      @cache.get 'my_namespace:key'
    end

    assert_equal 'some io error', e.message
  end

  def test_get_cache_get_SystemCallError
    socket = Object.new
    def socket.write(arg) raise SystemCallError, 'some syscall error'; end
    server = FakeServerDb.new socket

    @cache.servers = []
    @cache.servers << server

    e = assert_raise MemCacheDb::MemCacheDbError do
      @cache.get 'my_namespace:key'
    end

    assert_equal 'unknown error - some syscall error', e.message
  end

  def test_get_no_connection
    @cache.servers = 'localhost:1'
    e = assert_raise MemCacheDb::MemCacheDbError do
      @cache.get 'key'
    end

    assert_match /^No connection to server/, e.message
  end

  def test_get_no_servers
    @cache.servers = []
    e = assert_raise MemCacheDb::MemCacheDbError do
      @cache.get 'key'
    end

    assert_equal 'No active servers', e.message
  end

  def test_get_multi
    server = FakeServerDb.new
    server.socket.data.write "VALUE my_namespace:key 0 14\r\n"
    server.socket.data.write "\004\b\"\0170123456789\r\n"
    server.socket.data.write "VALUE my_namespace:keyb 0 14\r\n"
    server.socket.data.write "\004\b\"\0179876543210\r\n"
    server.socket.data.write "END\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    values = @cache.get_multi 'key', 'keyb'

    assert_equal "get my_namespace:key my_namespace:keyb\r\n",
                 server.socket.written.string

    expected = { 'key' => '0123456789', 'keyb' => '9876543210' }

    assert_equal expected.sort, values.sort
  end

  def test_get_raw
    server = FakeServerDb.new
    server.socket.data.write "VALUE my_namespace:key 0 10\r\n"
    server.socket.data.write "0123456789\r\n"
    server.socket.data.write "END\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server


    value = @cache.get 'key', true

    assert_equal "get my_namespace:key\r\n",
                 @cache.servers.first.socket.written.string

    assert_equal '0123456789', value
  end

  def test_get_server_for_key
    server = @cache.get_server_for_key 'key'
    assert_equal 'localhost', server.host
    assert_equal 1, server.port
  end

  def test_get_server_for_key_multiple
    s1 = util_setup_server @cache, 'one.example.com', ''
    s2 = util_setup_server @cache, 'two.example.com', ''
    @cache.servers = [s1, s2]

    server = @cache.get_server_for_key 'keya'
    assert_equal 'two.example.com', server.host
    server = @cache.get_server_for_key 'keyb'
    assert_equal 'two.example.com', server.host
    server = @cache.get_server_for_key 'keyc'
    assert_equal 'two.example.com', server.host
    server = @cache.get_server_for_key 'keyd'
    assert_equal 'one.example.com', server.host
  end

  def test_get_server_for_key_no_servers
    @cache.servers = []

    e = assert_raise MemCacheDb::MemCacheDbError do
      @cache.get_server_for_key 'key'
    end

    assert_equal 'No servers available', e.message
  end

  def test_get_server_for_key_spaces
    e = assert_raise ArgumentError do
      @cache.get_server_for_key 'space key'
    end
    assert_equal 'illegal character in key "space key"', e.message
  end

  def test_get_server_for_key_length
    @cache.get_server_for_key 'x' * 250
    long_key = 'x' * 251
    e = assert_raise ArgumentError do
      @cache.get_server_for_key long_key
    end
    assert_equal "key too long #{long_key.inspect}", e.message
  end

  def test_incr
    server = FakeServerDb.new
    server.socket.data.write "5\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    value = @cache.incr 'key'

    assert_equal "incr my_namespace:key 1\r\n",
                 @cache.servers.first.socket.written.string

    assert_equal 5, value
  end

  def test_incr_not_found
    server = FakeServerDb.new
    server.socket.data.write "NOT_FOUND\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    value = @cache.incr 'key'

    assert_equal "incr my_namespace:key 1\r\n",
                 @cache.servers.first.socket.written.string

    assert_equal nil, value
  end

  def test_incr_space_padding
    server = FakeServerDb.new
    server.socket.data.write "5 \r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    value = @cache.incr 'key'

    assert_equal "incr my_namespace:key 1\r\n",
                 @cache.servers.first.socket.written.string

    assert_equal 5, value
  end

  def test_make_cache_key
    assert_equal 'my_namespace:key', @cache.make_cache_key('key')
    @cache.namespace = nil
    assert_equal 'key', @cache.make_cache_key('key')
  end

  def test_servers
    server = FakeServerDb.new
    @cache.servers = []
    @cache.servers << server
    assert_equal [server], @cache.servers
  end

  def test_set
    server = FakeServerDb.new
    server.socket.data.write "STORED\r\n"
    server.socket.data.rewind
    @cache.servers = []
    @cache.servers << server

    @cache.set 'key', 'value'

    dumped = Marshal.dump('value')
    expected = "set my_namespace:key 0 0 #{dumped.length}\r\n#{dumped}\r\n"
#    expected = "set my_namespace:key 0 0 9\r\n\004\b\"\nvalue\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_set_expiry
    server = FakeServerDb.new
    server.socket.data.write "STORED\r\n"
    server.socket.data.rewind
    @cache.servers = []
    @cache.servers << server

    @cache.set 'key', 'value', 5

    dumped = Marshal.dump('value')
    expected = "set my_namespace:key 0 5 #{dumped.length}\r\n#{dumped}\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_set_raw
    server = FakeServerDb.new
    server.socket.data.write "STORED\r\n"
    server.socket.data.rewind
    @cache.servers = []
    @cache.servers << server

    @cache.set 'key', 'value', 0, true

    expected = "set my_namespace:key 0 0 5\r\nvalue\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_set_readonly
    cache = MemCacheDb.new :readonly => true

    e = assert_raise MemCacheDb::MemCacheDbError do
      cache.set 'key', 'value'
    end

    assert_equal 'Update of readonly cache', e.message
  end

  def test_set_too_big
    server = FakeServerDb.new

    # Write two messages to the socket to test failover
    server.socket.data.write "SERVER_ERROR\r\nSERVER_ERROR object too large for cache\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    e = assert_raise MemCacheDb::MemCacheDbError do
      @cache.set 'key', 'v'
    end

    assert_match /object too large for cache/, e.message
  end

  def test_add
    server = FakeServerDb.new
    server.socket.data.write "STORED\r\n"
    server.socket.data.rewind
    @cache.servers = []
    @cache.servers << server

    @cache.add 'key', 'value'
    
    dumped = Marshal.dump('value')

    expected = "add my_namespace:key 0 0 #{dumped.length}\r\n#{dumped}\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_add_exists
    server = FakeServerDb.new
    server.socket.data.write "NOT_STORED\r\n"
    server.socket.data.rewind
    @cache.servers = []
    @cache.servers << server

    @cache.add 'key', 'value'

    dumped = Marshal.dump('value')
    expected = "add my_namespace:key 0 0 #{dumped.length}\r\n#{dumped}\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_add_expiry
    server = FakeServerDb.new
    server.socket.data.write "STORED\r\n"
    server.socket.data.rewind
    @cache.servers = []
    @cache.servers << server

    @cache.add 'key', 'value', 5

    dumped = Marshal.dump('value')
    expected = "add my_namespace:key 0 5 #{dumped.length}\r\n#{dumped}\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_add_raw
    server = FakeServerDb.new
    server.socket.data.write "STORED\r\n"
    server.socket.data.rewind
    @cache.servers = []
    @cache.servers << server

    @cache.add 'key', 'value', 0, true

    expected = "add my_namespace:key 0 0 5\r\nvalue\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_add_raw_int
    server = FakeServerDb.new
    server.socket.data.write "STORED\r\n"
    server.socket.data.rewind
    @cache.servers = []
    @cache.servers << server

    @cache.add 'key', 12, 0, true

    expected = "add my_namespace:key 0 0 2\r\n12\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_add_readonly
    cache = MemCacheDb.new :readonly => true

    e = assert_raise MemCacheDb::MemCacheDbError do
      cache.add 'key', 'value'
    end

    assert_equal 'Update of readonly cache', e.message
  end

  def test_delete
    server = FakeServerDb.new
    @cache.servers = []
    @cache.servers << server
    
    @cache.delete 'key'
    
    expected = "delete my_namespace:key 0\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_delete_with_expiry
    server = FakeServerDb.new
    @cache.servers = []
    @cache.servers << server
    
    @cache.delete 'key', 300
    
    expected = "delete my_namespace:key 300\r\n"
    assert_equal expected, server.socket.written.string
  end

  def test_flush_all
    @cache.servers = []
    3.times { @cache.servers << FakeServerDb.new }

    @cache.flush_all

    expected = "flush_all\r\n"
    @cache.servers.each do |server|
      assert_equal expected, server.socket.written.string
    end
  end

  def test_flush_all_failure
    socket = FakeSocketDb.new

    # Write two messages to the socket to test failover
    socket.data.write "ERROR\r\nERROR\r\n"
    socket.data.rewind

    server = FakeServerDb.new socket

    @cache.servers = []
    @cache.servers << server

    assert_raise MemCacheDb::MemCacheDbError do
      @cache.flush_all
    end

    assert_match /flush_all\r\n/, socket.written.string
  end

  def test_stats
    socket = FakeSocketDb.new
    socket.data.write "STAT pid 20188\r\nSTAT total_items 32\r\nSTAT version 1.2.3\r\nSTAT rusage_user 1:300\r\nSTAT dummy ok\r\nEND\r\n"
    socket.data.rewind
    server = FakeServerDb.new socket
    def server.host() 'localhost'; end
    def server.port() 11211; end

    @cache.servers = []
    @cache.servers << server

    expected = {
      'localhost:21201' => {
        'pid' => 20188, 'total_items' => 32, 'version' => '1.2.3',
        'rusage_user' => 1.0003, 'dummy' => 'ok'
      }
    }
    assert_equal expected, @cache.stats

    assert_equal "stats\r\n", socket.written.string
  end

  def test_basic_threaded_operations_should_work
    cache = MemCacheDb.new :multithread => true,
                         :namespace => 'my_namespace',
                         :readonly => false

    server = FakeServerDb.new
    server.socket.data.write "STORED\r\n"
    server.socket.data.rewind

    cache.servers = []
    cache.servers << server

    assert cache.multithread

    assert_nothing_raised do
      cache.set "test", "test value"
    end

    output = server.socket.written.string
    assert_match /set my_namespace:test/, output
    assert_match /test value/, output
  end

  def test_basic_unthreaded_operations_should_work
    cache = MemCacheDb.new :multithread => false,
                         :namespace => 'my_namespace',
                         :readonly => false

    server = FakeServerDb.new
    server.socket.data.write "STORED\r\n"
    server.socket.data.rewind

    cache.servers = []
    cache.servers << server

    assert !cache.multithread

    assert_nothing_raised do
      cache.set "test", "test value"
    end

    output = server.socket.written.string
    assert_match /set my_namespace:test/, output
    assert_match /test value/, output
  end

  def util_setup_fake_server
    server = FakeServerDb.new
    server.socket.data.write "VALUE my_namespace:key 0 14\r\n"
    server.socket.data.write "\004\b\"\0170123456789\r\n"
    server.socket.data.write "END\r\n"
    server.socket.data.rewind

    @cache.servers = []
    @cache.servers << server

    return server
  end

  def util_setup_server(memcache, host, responses)
    server = MemCacheDb::Server.new memcache, host
    server.instance_variable_set :@sock, StringIO.new(responses)

    @cache.servers = []
    @cache.servers << server

    return server
  end

end

