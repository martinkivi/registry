class AddressVersion < PaperTrail::Version
  include VersionSession
  self.table_name    = :log_addresses
  self.sequence_name = :log_addresses_id_seq
end
