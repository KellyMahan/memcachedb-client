##
# A utility wrapper around the MemCacheDb client to simplify cache access.  All
# methods silently ignore MemCacheDb errors.

module CacheDb
  
  ##
  # Try to return a logger object that does not rely
  # on ActiveRecord for logging.
  def self.logger
    @logger ||= if defined? Rails.logger # Rails 2.1 +
      Rails.logger
    elsif defined? RAILS_DEFAULT_LOGGER # Rails 1.2.2 +
      RAILS_DEFAULT_LOGGER
    else
      ActiveRecord::Base.logger # ... very old Rails.
    end
  end
  ##
  # Returns the object at +key+ from the cache if successful, or nil if either
  # the object is not in the cache or if there was an error attermpting to
  # access the cache.
  #
  # If there is a cache miss and a block is given the result of the block will
  # be stored in the cache with optional +expiry+, using the +add+ method rather
  # than +set+.

  def self.get(key, expiry = 0)
    start_time = Time.now
    value = CACHE.get key
    elapsed = Time.now - start_time
    logger.debug('MemCacheDb Get (%0.6f)  %s' % [elapsed, key])
    if value.nil? and block_given? then
      value = yield
      add key, value, expiry
    end
    value
  rescue MemCacheDb::MemCacheDbError => err
    logger.debug "MemCacheDb Error: #{err.message}"
    if block_given? then
      value = yield
      put key, value, expiry
    end
    value
  end

  ##
  # Sets +value+ in the cache at +key+, with an optional +expiry+ time in
  # seconds.

  def self.put(key, value, expiry = 0)
    start_time = Time.now
    CACHE.set key, value, expiry
    elapsed = Time.now - start_time
    logger.debug('MemCacheDb Set (%0.6f)  %s' % [elapsed, key])
    value
  rescue MemCacheDb::MemCacheDbError => err
    ActiveRecord::Base.logger.debug "MemCacheDb Error: #{err.message}"
    nil
  end

  ##
  # Sets +value+ in the cache at +key+, with an optional +expiry+ time in
  # seconds.  If +key+ already exists in cache, returns nil.

  def self.add(key, value, expiry = 0)
    start_time = Time.now
    response = CACHE.add key, value, expiry
    elapsed = Time.now - start_time
    logger.debug('MemCacheDb Add (%0.6f)  %s' % [elapsed, key])
    (response == "STORED\r\n") ? value : nil
  rescue MemCacheDb::MemCacheDbError => err
    ActiveRecord::Base.logger.debug "MemCacheDb Error: #{err.message}"
    nil
  end

  ##
  # Deletes +key+ from the cache in +delay+ seconds.

  def self.delete(key, delay = nil)
    start_time = Time.now
    CACHE.delete key, delay
    elapsed = Time.now - start_time
    logger.debug('MemCacheDb Delete (%0.6f)  %s' %
                                    [elapsed, key])
    nil
  rescue MemCacheDb::MemCacheDbError => err
    logger.debug "MemCacheDb Error: #{err.message}"
    nil
  end

  ##
  # Resets all connections to MemCacheDb servers.

  def self.reset
    CACHE.reset
    logger.debug 'MemCacheDb Connections Reset'
    nil
  end

end

