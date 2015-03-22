require "./mysql/*"

# MySQL connection class. Allows high-level interaction with mysql
# through LibMySQL.
#
# NOTE:
# The @handle is totally not threadsafe, because it is stateful. So if
# concurrency is needed, then each concurrent task should own its own
# connection.
class MySQL
  class Error < Exception; end
  class ConnectionError < Error; end
  class NotConnectedError < Error; end
  class QueryError < Error; end

  alias SqlTypes = String|Int32|Float64|UInt64|Nil

  struct ValueReader
    property value :: SqlTypes
    property start

    def initialize(@value, @start)
    end

    def initialize
      @value = ""
      @start = 0
    end
  end

  INTEGER_TYPES = [
                   LibMySQL::MySQLFieldType::MYSQL_TYPE_TINY,
                   LibMySQL::MySQLFieldType::MYSQL_TYPE_SHORT,
                   LibMySQL::MySQLFieldType::MYSQL_TYPE_LONG,
                   LibMySQL::MySQLFieldType::MYSQL_TYPE_LONGLONG,
                   LibMySQL::MySQLFieldType::MYSQL_TYPE_INT24,
                  ]

  FLOAT_TYPES = [
                 LibMySQL::MySQLFieldType::MYSQL_TYPE_DECIMAL,
                 LibMySQL::MySQLFieldType::MYSQL_TYPE_FLOAT,
                 LibMySQL::MySQLFieldType::MYSQL_TYPE_DOUBLE,
                 LibMySQL::MySQLFieldType::MYSQL_TYPE_NEWDECIMAL,
                ]

  def initialize
    @handle = LibMySQL.init(nil)
    @connected = false
  end

  def client_info
    String.new LibMySQL.client_info
  end

  def error
    String.new LibMySQL.error(@handle)
  end

  def escape_string(original)
    # NOTE: This is how you create a new pointer!
    new = Pointer(UInt8).malloc(0)
    LibMySQL.escape_string(@handle, new, original, original.length.to_u32)
    String.new(new)
  end

  def connect(host, user, pass, db, port, socket, flags = 0_u32)
    handle = LibMySQL.real_connect(@handle, host, user, pass, db, port, socket,
                                   flags)
    if handle == @handle
      @connected = true
    elsif handle.nil?
      raise ConnectionError.new(error)
    else
      raise ConnectionError.new("Unreachable code")
    end

    self
  end

  # @non-threadsafe!
  def query(query_string)
    unless @connected
      raise NotConnectedError.new
    end

    code = LibMySQL.query(@handle, query_string)
    raise QueryError.new(error) if code != 0
    result = LibMySQL.store_result(@handle)
    return nil if result.nil?

    fields = [] of LibMySQL::MySQLField
    while field = LibMySQL.fetch_field(result)
      fields << field.value
    end

    rows = [] of Array(SqlTypes)
    while row = fetch_row(result, fields)
      rows << row
    end

    # NOTE: Why this happens here:
    # *** Error in `/tmp/crystal-run-spec.CAKQ1K': double free or corruption (out): 0x00000000008fa040 ***
    #LibMySQL.free_result(result)

    rows
  end

  def fetch_row(result, fields)
    row = LibMySQL.fetch_row(result)
    return nil if row.nil?

    reader = ValueReader.new
    row_list = [] of SqlTypes
    fields.each do |field|
      reader = fetch_value(field, row, reader)
      row_list << reader.value
    end

    row_list
  end

  def fetch_value(field, source, reader)
    len = field.max_length
    value = string_from_uint8(source[0] + reader.start, len)
    if len > 0 && value[-1] == '\0'
      value = value[0...-1]
      len -= 1
    end

    if INTEGER_TYPES.includes?(field.field_type)
      value = value.to_i
    end

    if FLOAT_TYPES.includes?(field.field_type)
      value = value.to_f
    end

    if field.field_type == LibMySQL::MySQLFieldType::MYSQL_TYPE_NULL
      value = nil
      len = -1
    end

    reader.start += len + 1
    reader.value = value
    reader
  end

  def string_from_uint8(s, len)
    (0_u64...len).inject("") { |acc, i| acc + s[i].chr }
  end
end
