
require 'mongo'


module Kongo

  class Collection

    # Initialize with a collection name (as symbol), will use that collection
    # name to generate the connection lazily when it is first used, thru the
    # collection callback (*must* be defined).
    #
    def initialize(name)
      @coll_name = name
      @visible_ivars = []
      @@extensions ||= {}

      if @@extensions[name.to_sym]
        @@extensions[name.to_sym].each do |const|
          extend(const)
        end
      end
    end

    # When passed a native BSON::ObjectId, it will act as a find_by_id,
    # otherwise, expects a regular query hash. Will return a Kongo::Model.
    #
    def find_one(*args)
      (r = coll.find_one(*args)) ?
        Model.new(r, coll) : r
    end

    # If passed a legal BSON ObjectId string, will convert to BSON::ObjectId.
    # Otherwise finds by value.
    #
    def find_by_id(id)
      id = BSON::ObjectId(id) if id.is_a?(String) && BSON::ObjectId.legal?(id)
      find_one(_id: id)
    end

    # `find`, aka. `find_many` returns a Kongo::Cursor wrapping the Mongo
    # cursor.
    #
    def find(*args)
      (c = coll.find(*args)).is_a?(::Mongo::Cursor) ?
        Cursor.new(c, coll) : c
    end
    alias :find_many :find

    # Count, just forwards to driver.
    #
    def count(*args)
      coll.count(*args)
    end

    # Verify existence of record by id.
    #
    def has?(id)
      count(:query => {_id: id}) == 1
    end

    # Insert a record, returns a Model object.
    #
    def insert!(hash)
      coll.insert(hash)
      hash['_id'] = hash.delete(:_id) if hash[:_id]
      Model.new(hash, coll)
    end

    # Collection#extend adds the option of extending with a symbol, which
    # will automatically use that constant from Extensions::Collections,
    # calls super in every other case.
    #
    def extend(arg)
      super(arg.is_a?(Symbol) ? Extensions::Collections.const_get(arg) : arg)
    end


    # This method must be called statically on the ORM once before being used,
    # so that the ORM knows how to connect to mongo and fetch collections.
    #
    # A simple usage example might look like this:
    #
    #   class MongoCollectionFetcher
    #     def self.fetch(name)
    #       @mongo ||= Mongo::Connection.new
    #       return @mongo['database'][name.to_s]
    #     end
    #   end
    #
    #   Kongo::Collection.fetch_collections_using do |n|
    #     MongoCollectionFetcher.fetch(n)
    #   end
    #
    def self.fetch_collections_using(&block)
      @@collection_fetcher = block
    end


    # This method returns the Mongo::Collection object for this collection.
    #
    def coll
      return @coll if @coll

      @coll ||= begin
        raise 'Kongo has not been initialized with a collection fetcher.' unless @@collection_fetcher
        @@collection_fetcher.call(@coll_name)
      end
    end



    # Inspecting a Mongo Model attempts to only show *useful* information,
    # such as what its extensions are as well as certain ivars.
    #
    def inspect
      proxy = Object.new
      @visible_ivars.each do |ivar|
        val = instance_variable_get(ivar)
        proxy.instance_variable_set(ivar, val) unless val.nil?
      end
      string = proxy.inspect
      ext_info = @extensions ? '(+ '+@extensions.join(', ')+')' : ''
      string.gsub(/Object:0x[0-9a-f]+/, "Kongo::Collection#{ext_info}:0x#{object_id}")
    end


    # Declare extensions using this method:
    #
    #   Kongo::Collection.add_extension(:collection_name, module)
    #
    def self.add_extension(collection_name, mod)
      ((@@extensions ||= {})[collection_name.to_sym] ||= []) << mod
    end

    # This method just adds the extension to the list of extension, for the
    # sake of inspect, and call super:
    #
    def extend(const)
      (@extensions ||= []) << const.to_s
      super
    end

  end


  # Cursor is an object that wraps around a Mongo::Cursor, wrapping objects it
  # returns in Kongo::Model objects.
  #
  class Cursor

    # `initialize` is typically only used internally by Kongo::Collection when
    # it returns cursors.
    #
    def initialize(cursor, coll)
      @coll = coll
      @cursor = cursor
    end

    # Any method is forwarded to its wrapped cursor.
    #
    def method_missing(*args, &block)
      @cursor.send(*args, &block)
    end

    # `next` wraps responses in Kongo::Model.
    #
    def next
      (e = @cursor.next).is_a?(Hash) ?
        Model.new(e, @coll) : e
    end

    # `each` yields Kongo::Model objects.
    #
    def each
      @cursor.each { |e| yield Model.new(e, @coll) }
    end

    # `to_enum` returns an Enumerator which yields the results of the cursor.
    #
    def to_enum
      Enumerator.new do |yielder|
        while @cursor.has_next?
          yielder.yield(self.next)
        end
      end
    end

    # `to_a` returns an array of Kongo::Model.
    #
    def to_a
      arr = []
      each { |e| arr << e }
      arr
    end
  end


  # Kongo::Model is the most important class of Kongo, it wraps around hashes
  # representing Mongo records, provides a collection of useful methods, and
  # allows itself to be extended by third party libraries.
  #
  class Model

    # Typically, you would not call Model#new directly, but rather get
    # a model from a method on Collections, such as a finder or #insert.
    #
    def initialize(hash, coll)
      @coll = coll
      @hash = hash
      @deltas = {}
      @visible_ivars = [:@hash, :@deltas]
      @@extensions ||= {}

      if @@extensions[coll.name.to_sym]
        @@extensions[coll.name.to_sym].each do |const|
          extend(const)
        end
      end
    end

    attr_reader :hash
    attr_reader :deltas

    # Record fields can be accessed using [] syntax.
    #
    def [](k); @hash[k]; end

    # This adds to the list of deltas, so that we may update with no
    # arguments below
    #
    def []=(k,v)
      @hash[k.to_s]=v

      delta('$set', k => v)
    end

    # Default comparison is via the string version of the id.
    #
    # @example Compare two models.
    #   person <=> other_person
    #
    # @param [ Kongo::Model ] other The document to compare with.
    #
    # @return [ Integer ] -1, 0, 1.
    #
    def <=>(other)
      self['_id'].to_s <=> other['_id'].to_s
    end

    # Performs equality checking on the document ids.
    #
    # @example Compare for equality.
    #   model == other
    #
    # @param [ Kongo::Model, Object ] other The other object to compare with.
    #
    # @return [ true, false ] True if the ids are equal, false if not.
    #
    def ==(other)
      self.class == other.class &&
        self['_id'] == other['_id']
    end

    # Add a delta
    #
    #   delta '$inc',
    #     total: 3,
    #     unique: 1
    #
    def delta(type, fields = {})
      fields.each do |k,v|
        @deltas[type.to_s] ||= {}
        @deltas[type.to_s][k.to_s] = v
      end
      self
    end

    # `unset` lets you remove a key from the hash, as well as adding it to
    # the deltas so that the next update will unset that key in Mongo.
    #
    def unset(key)
      @hash.delete(key.to_s)
      delta('$unset', key => 1)
    end

    # This method_missing provides accessors for keys as proprieties of the
    # model object, so you may do:
    #
    #   object.key = :value
    #   object.key #=> :value
    #
    def method_missing(key, *args, &block)
      key = key.to_s
      if matches = /^(.+)=$/.match(key)
        raise ArgumentError.new 'Unexpected argument count.' if args.count != 1
        self[matches[1]] = args.first
      else
        raise ArgumentError.new 'Unexpected argument count.' if args.count != 0
        return self[key]
      end
    end

    # @deprecated
    # Do not use saves, they're dirty.
    #
    def save!(options = {})
      warn("#{Kernel.caller.first}: `save` is deprecated, use `update` instead.")
      raise if @stale unless options[:ignore_stale] # TODO: custom exception
      @coll.save(@hash, :w => 1)
    end

    # Issues an update on the database, for this record, with the provided
    # deltas. WARNING: the record will become stale, and should no longer be
    # saved after an update has been issued.
    #
    def update!(deltas = {})
      return if @deltas.empty? && deltas.empty?

      id = @hash['_id']
      raise unless id # TODO: custom exception

      if @deltas
        deltas = @deltas.merge(deltas)
        @deltas = {}
      end

      @stale = true

      @coll.update({_id: id}, deltas, :w => 1)
    end

    # Deletes this record from the database.
    #
    def delete!
      id = @hash['_id']
      raise unless id # TODO: custom exception
      @coll.remove({_id: id})
    end

    # Returns the hash of the record itself.
    #
    def to_hash
      @hash
    end

    # Inspecting a Mongo Model attempts to only show *useful* information,
    # such as what its extensions are as well as certain ivars.
    #
    def inspect
      proxy = Object.new
      @visible_ivars.each do |ivar|
        val = instance_variable_get(ivar)
        proxy.instance_variable_set(ivar, val) unless val.nil?
      end
      string = proxy.inspect
      ext_info = @extensions ? '(+ '+@extensions.join(', ')+')' : ''
      string.gsub(/Object:0x[0-9a-f]+/, "Kongo::Model#{ext_info}:0x#{object_id}")
    end



    # Declare extensions using this method:
    #
    #   Kongo::Model.add_extension(:collection_name, module)
    #
    def self.add_extension(collection_name, mod)
      ((@@extensions ||= {})[collection_name.to_sym] ||= []) << mod
    end

    # This method just adds the extension to the list of extension, for the
    # sake of inspect, and call super:
    #
    def extend(const)
      (@extensions ||= []) << const.to_s
      super
    end

  end

end
