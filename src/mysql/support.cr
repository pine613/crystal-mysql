module MySQL
  module Support
    EMPTY_HANDLE = LibMySQL.init(nil)

    def self.escape_string(original)
      new = Pointer(UInt8).malloc(0)
      LibMySQL.escape_string(EMPTY_HANDLE, new, original, original.length.to_u32)
      String.new(new)
    end

    def self.string_from_uint8(s, len)
      String.new(s, len)
    end
  end
end
