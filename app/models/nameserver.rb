class Nameserver < ActiveRecord::Base
  include Versions # version/nameserver_version.rb
  include EppErrors

  # belongs_to :registrar
  belongs_to :domain

  # scope :owned_by_registrar, -> (registrar) { joins(:domain).where('domains.registrar_id = ?', registrar.id) }

  # rubocop: disable Metrics/LineLength
  validates :hostname, format: { with: /\A(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])\z/ }
  validates :ipv4, format: { with: /\A(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\z/, allow_blank: true }
  validates :ipv6, format: { with: /(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]).){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]).){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))/, allow_blank: true }
  # rubocop: enable Metrics/LineLength

  before_validation :normalize_attributes

  delegate :name, to: :domain, prefix: true

  def epp_code_map
    {
      '2302' => [
        [:hostname, :taken, { value: { obj: 'hostAttr', val: hostname } }]
      ],
      '2005' => [
        [:hostname, :invalid, { value: { obj: 'hostAttr', val: hostname } }],
        [:ipv4, :invalid, { value: { obj: 'hostAddr', val: ipv4 } }],
        [:ipv6, :invalid, { value: { obj: 'hostAddr', val: ipv6 } }]
      ],
      '2306' => [
        [:ipv4, :blank]
      ]
    }
  end

  def normalize_attributes
    self.hostname = hostname.try(:strip).try(:downcase)
    self.ipv4 = ipv4.try(:strip)
    self.ipv6 = ipv6.try(:strip).try(:upcase)
  end

  def to_s
    hostname
  end

  class << self
    def replace_hostname_ends(domains, old_end, new_end)
      domains = domains.where('EXISTS(
          select 1 from nameservers ns where ns.domain_id = domains.id AND ns.hostname LIKE ?
        )', "%#{old_end}")

      count, success_count = 0.0, 0.0
      domains.each do |d|
        ns_attrs = { nameservers_attributes: [] }

        d.nameservers.each do |ns|
          next unless ns.hostname.end_with?(old_end)

          hn = ns.hostname.chomp(old_end)
          ns_attrs[:nameservers_attributes] << {
            id: ns.id,
            hostname: "#{hn}#{new_end}"
          }
        end

        success_count += 1 if d.update(ns_attrs)
        count += 1
      end

      return 'replaced_none' if count == 0.0

      prc = success_count / count

      return 'replaced_all' if prc == 1.0
      'replaced_some'
    end
  end
end
