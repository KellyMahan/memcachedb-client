= memcache-client

A pure ruby library for accessing memcached.

Rubyforge Project:

http://rubyforge.org/projects/seattlerb

Source:

http://github.com/mperham/memcache-client

== Installing memcache-client

Just install the gem:

  $ sudo gem install memcache-client

== Using memcache-client

With one server:

  CACHE = MemCache.new 'localhost:11211', :namespace => 'my_namespace'

Or with multiple servers:

  CACHE = MemCache.new %w[one.example.com:11211 two.example.com:11211],
                       :namespace => 'my_namespace'

See MemCache.new for details.  Please note memcache-client is not thread-safe
by default.  You should create a separate instance for each thread in your
process.

== Using memcache-client with Rails

There's no need to use memcache-client directly from Rails.  Rails 2.1+ includes
a basic caching library which can be used with memcached.  See ActiveSupport::Cache::Store
for more details.

== Questions?

memcache-client is maintained by Mike Perham.

Email: mperham@gmail.com
Twitter: mperham
WWW: http://mikeperham.com
