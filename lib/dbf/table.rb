module DBF

  class Table
    attr_reader :column_count           # The total number of columns
    attr_reader :columns                # An array of DBF::Column
    attr_reader :version                # Internal dBase version number
    attr_reader :last_updated           # Last updated datetime
    attr_reader :memo_file_format       # :fpt or :dpt
    attr_reader :memo_block_size        # The block size for memo records
    attr_reader :options                # The options hash that was used to initialize the table
    attr_reader :data                   # DBF file handle
    attr_reader :memo                   # Memo file handle
    attr_reader :record_count           # Total number of records
    
    # Initializes a new DBF::Table
    # Example:
    #   table = DBF::Table.new 'data.dbf'
    def initialize(filename, options = {})
      @data = File.open(filename, 'rb')
      @memo = open_memo(filename)
      @options = options
      reload!
    end
    
    # Reloads the database and memo files
    def reload!
      @records = nil
      get_header_info
      get_memo_header_info if @memo
      get_column_descriptors
    end
    
    # Returns true if there is a corresponding memo file
    def has_memo_file?
      @memo ? true : false
    end
    
    # Returns an instance of DBF::Column for <b>column_name</b>.  The <b>column_name</b>
    # can be a specified as either a symbol or string.
    def column(column_name)
      @columns.detect {|f| f.name == column_name.to_s}
    end
    
    def each
      0.upto(@record_count - 1) do |n|
        seek_to_record(n)
        yield deleted_record? ? nil : DBF::Record.new(self)
      end
    end
    
    # Returns the DBF::Record at the specified index
    def record(index)
      seek_to_record(index)
      DBF::Record.new(self)
    end
    
    alias_method :row, :record
    
    # Returns a description of the current database file.
    def version_description
      VERSION_DESCRIPTIONS[version]
    end
    
    # Returns a database schema in the portable ActiveRecord::Schema format.
    # 
    # xBase data types are converted to generic types as follows:
    # - Number columns are converted to :integer if there are no decimals, otherwise
    #   they are converted to :float
    # - Date columns are converted to :datetime
    # - Logical columns are converted to :boolean
    # - Memo columns are converted to :text
    # - Character columns are converted to :string and the :limit option is set
    #   to the length of the character column
    #
    # Example:
    #   create_table "mydata" do |t|
    #     t.column :name, :string, :limit => 30
    #     t.column :last_update, :datetime
    #     t.column :is_active, :boolean
    #     t.column :age, :integer
    #     t.column :notes, :text
    #   end
    def schema(path = nil)
      s = "ActiveRecord::Schema.define do\n"
      s << "  create_table \"#{File.basename(@data.path, ".*")}\" do |t|\n"
      columns.each do |column|
        s << "    t.column #{column.schema_definition}"
      end
      s << "  end\nend"
      
      if path
        File.open(path, 'w') {|f| f.puts(s)}
      else
        s
      end
    end
    
    # Dumps all records into a CSV file
    def to_csv(filename = nil)
      filename = File.basename(@data.path, '.dbf') + '.csv' if filename.nil?
      FCSV.open(filename, 'w', :force_quotes => true) do |csv|
        each do |record|
          csv << record.to_a
        end
      end
    end
    
    private
    
    def open_memo(file)
      %w(fpt FPT dbt DBT).each do |extname|
        filename = replace_extname(file, extname)
        if File.exists?(filename)
          @memo_file_format = extname.downcase.to_sym
          return File.open(filename, 'rb')
        end
      end
      nil
    end
    
    def replace_extname(filename, extension)
      filename.sub(/#{File.extname(filename)[1..-1]}$/, extension)
    end
  
    def deleted_record?
      if @data.read(1).unpack('a') == ['*']
        @data.rewind
        true
      else
        false
      end
    end
  
    def get_header_info
      @data.rewind
      @version, @record_count, @header_length, @record_length = @data.read(DBF_HEADER_SIZE).unpack('H2 x3 V v2')
      @column_count = (@header_length - DBF_HEADER_SIZE + 1) / DBF_HEADER_SIZE
    end
  
    def get_column_descriptors
      @columns = []
      @column_count.times do
        name, type, length, decimal = @data.read(32).unpack('a10 x a x4 C2')
        if length > 0
          @columns << Column.new(name.strip, type, length, decimal)
        end
      end
      # Reset the column count in case any were skipped
      @column_count = @columns.size
      
      @columns
    end
  
    def get_memo_header_info
      @memo.rewind
      if @memo_file_format == :fpt
        @memo_next_available_block, @memo_block_size = @memo.read(FPT_HEADER_SIZE).unpack('N x2 n')
        @memo_block_size = 0 if @memo_block_size.nil?
      else
        @memo_block_size = 512
        @memo_next_available_block = File.size(@memo.path) / @memo_block_size
      end
    end
  
    def seek(offset)
      @data.seek(@header_length + offset)
    end
  
    def seek_to_record(index)
      seek(index * @record_length)
    end
    
  end
  
end