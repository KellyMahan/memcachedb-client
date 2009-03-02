Gem::Specification.new do |s|
	s.name = 'memcachedb-client'
	s.version = '1.1.3'
	s.authors = ['Kelly Mahan']
	s.email = 'kellymahan@gmail.com'
	s.homepage = 'http://github.com/KellyMahan/memcachedb-client'
	s.summary = 'A Ruby library for accessing memcachedb. Forked from memcache-client'
	s.description = s.summary

	s.require_path = 'lib'

	s.files = ["README.rdoc", "LICENSE.txt", "History.txt", "Rakefile", "lib/memcache_db.rb"]
	s.test_files = ["test/test_mem_cache_db.rb"]
	s.add_dependency ['RubyInline']
end
