class ZonefileSettingVersion < PaperTrail::Version
  include VersionSession
  self.table_name    = :log_zonefile_settings
  self.sequence_name = :log_zonefile_settings_id_seq
end
