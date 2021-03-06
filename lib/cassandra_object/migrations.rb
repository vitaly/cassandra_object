module CassandraObject
  module Migrations
    extend ActiveSupport::Concern
    included do
      cattr_accessor :migration_column_name
      self.migration_column_name = :schema_version
      class_inheritable_array :migrations
      class_inheritable_accessor :current_schema_version
      self.current_schema_version = 0
    end
    
    class Migration
      attr_reader :version
      def initialize(version, block)
        @version = version
        @block = block
      end
      
      def run(attrs)
        @block.call(attrs)
      end
    end
    
    class MigrationNotFoundError < StandardError
      def initialize(record_version, migrations)
        super("Cannot migrate a record from #{record_version.inspect}.  Migrations exist for #{migrations.map(&:version)}")
      end
    end
    
    module InstanceMethods
      def schema_version
        Integer(@schema_version || self.class.current_schema_version)
      end
    end
    
    module ClassMethods
      def migrate(version, &blk)
        write_inheritable_array(:migrations, [Migration.new(version, blk)])
        
        if version > self.current_schema_version 
          self.current_schema_version = version
        end
      end
      
      def instantiate(key, attributes)
        original_attributes = attributes.dup
        version = attributes[migration_column_name.to_s]
        if version == current_schema_version
          return super(key, attributes)
        end
        
        versions_to_migrate = ((version.to_i + 1)..current_schema_version)
        
        migrations_to_run = versions_to_migrate.map do |v|
          migrations.find {|m| m.version == v}
        end
        
        if migrations_to_run.any?(&:nil?)
          raise MigrationNotFoundError.new(version, migrations)
        end
        
        migrations_to_run.inject(attributes) do |attrs, migration|
          migration.run(attrs)
          attrs[migration_column_name.to_s] = migration.version.to_s
          attrs
        end
        
        returning super(key, attributes) do |record|
          record.attributes_changed!(original_attributes.diff(attributes).keys)
        end
      end
    end
  end
end