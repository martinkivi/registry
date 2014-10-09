Fabricator(:setting_group) do
  code 'domain_validation'
  settings do
    [
      Fabricate(:setting, code: 'ns_min_count', value: 1),
      Fabricate(:setting, code: 'ns_max_count', value: 13)
    ]
  end
end

Fabricator(:domain_validation_setting_group, from: :setting_group) do
  code 'domain_validation'
  settings do
    [
      Fabricate(:setting, code: 'ns_min_count', value: 1),
      Fabricate(:setting, code: 'ns_max_count', value: 13),
      Fabricate(:setting, code: 'dnskeys_min_count', value: 0),
      Fabricate(:setting, code: 'dnskeys_max_count', value: 9)
    ]
  end
end

Fabricator(:domain_statuses_setting_group, from: :setting_group) do
  code 'domain_statuses'
  settings do
    [
      Fabricate(:setting, code: 'client_hold', value: 'clientHold'),
      Fabricate(:setting, code: 'client_update_prohibited', value: 'clientUpdateProhibited')
    ]
  end
end

Fabricator(:domain_general_setting_group, from: :setting_group) do
  code 'domain_general'
  settings do
    [
      Fabricate(:setting, code: 'transfer_wait_time', value: '0')
    ]
  end
end

Fabricator(:dnskeys_setting_group, from: :setting_group) do
  code 'dnskeys'
  settings do
    [
      Fabricate(:setting, code: Setting::DS_ALGORITHM, value: 1),
      Fabricate(:setting, code: Setting::ALLOW_DS_DATA, value: 1),
      Fabricate(:setting, code: Setting::ALLOW_DS_DATA_WITH_KEYS, value: 1),
      Fabricate(:setting, code: Setting::ALLOW_KEY_DATA, value: 1)
    ]
  end
end
