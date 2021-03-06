# rubocop: disable Metrics/ClassLength
class Domain < ActiveRecord::Base
  include Versions # version/domain_version.rb
  include Statuses
  has_paper_trail class_name: "DomainVersion", meta: { children: :children_log }

  # TODO: whois requests ip whitelist for full info for own domains and partial info for other domains
  # TODO: most inputs should be trimmed before validatation, probably some global logic?

  belongs_to :registrar
  belongs_to :registrant

  has_many :domain_contacts, dependent: :destroy
  has_many :admin_domain_contacts
  accepts_nested_attributes_for :admin_domain_contacts, allow_destroy: true
  has_many :tech_domain_contacts
  accepts_nested_attributes_for :tech_domain_contacts, allow_destroy: true

  has_many :contacts, through: :domain_contacts, source: :contact
  has_many :admin_contacts, through: :admin_domain_contacts, source: :contact
  has_many :tech_contacts, through: :tech_domain_contacts, source: :contact
  has_many :nameservers, dependent: :destroy

  accepts_nested_attributes_for :nameservers, allow_destroy: true,
                                              reject_if: proc { |attrs| attrs[:hostname].blank? }

  has_many :domain_statuses, dependent: :destroy
  accepts_nested_attributes_for :domain_statuses, allow_destroy: true,
                                                  reject_if: proc { |attrs| attrs[:value].blank? }

  has_many :domain_transfers, dependent: :destroy

  has_many :dnskeys, dependent: :destroy

  has_many :keyrelays
  has_one :whois_record, dependent: :destroy

  accepts_nested_attributes_for :dnskeys, allow_destroy: true

  has_many :legal_documents, as: :documentable
  accepts_nested_attributes_for :legal_documents, reject_if: proc { |attrs| attrs[:body].blank? }

  delegate :name,    to: :registrant, prefix: true
  delegate :code,    to: :registrant, prefix: true
  delegate :ident,   to: :registrant, prefix: true
  delegate :email,   to: :registrant, prefix: true
  delegate :phone,   to: :registrant, prefix: true
  delegate :street,  to: :registrant, prefix: true
  delegate :city,    to: :registrant, prefix: true
  delegate :zip,     to: :registrant, prefix: true
  delegate :state,   to: :registrant, prefix: true
  delegate :country, to: :registrant, prefix: true

  delegate :name,   to: :registrar, prefix: true
  delegate :street, to: :registrar, prefix: true

  after_initialize do
    self.pending_json = {} if pending_json.blank?
    self.statuses = [] if statuses.nil?
    self.status_notes = {} if status_notes.nil?
  end

  before_create :generate_auth_info
  before_create :set_validity_dates
  before_create -> { self.reserved = in_reserved_list?; nil }

  before_save :manage_automatic_statuses
  before_save :touch_always_version
  def touch_always_version
    self.updated_at = Time.zone.now
  end

  before_update :manage_statuses
  def manage_statuses
    return unless registrant_id_changed? # rollback has not yet happened
    pending_update! if registrant_verification_asked?
    true
  end

  after_save :update_whois_record

  after_create :update_reserved_domains
  def update_reserved_domains
    return unless in_reserved_list?
    rd = ReservedDomain.first
    rd.names[name] = SecureRandom.hex
    rd.save
  end

  validates :name_dirty, domain_name: true, uniqueness: true
  validates :puny_label, length: { maximum: 63 }
  validates :period, numericality: { only_integer: true }
  validates :registrant, :registrar, presence: true

  validate :validate_period
  validate :validate_reservation
  def validate_reservation
    return if persisted? || !in_reserved_list?

    if reserved_pw.blank?
      errors.add(:base, :required_parameter_missing_reserved)
      return false
    end

    return if ReservedDomain.pw_for(name) == reserved_pw
    errors.add(:base, :invalid_auth_information_reserved)
  end

  validate :check_permissions
  def check_permissions
    return unless force_delete?
    errors.add(:base, I18n.t(:object_status_prohibits_operation))
    false
  end

  validates :nameservers, object_count: {
    min: -> { Setting.ns_min_count },
    max: -> { Setting.ns_max_count }
  }

  validates :dnskeys, object_count: {
    min: -> { Setting.dnskeys_min_count },
    max: -> { Setting.dnskeys_max_count }
  }

  validates :admin_domain_contacts, object_count: {
    min: -> { Setting.admin_contacts_min_count },
    max: -> { Setting.admin_contacts_max_count }
  }

  validates :tech_domain_contacts, object_count: {
    min: -> { Setting.tech_contacts_min_count },
    max: -> { Setting.tech_contacts_max_count }
  }

  validates :nameservers, uniqueness_multi: {
    attribute: 'hostname'
  }

  validates :tech_domain_contacts, uniqueness_multi: {
    attribute: 'contact_code_cache'
  }

  validates :admin_domain_contacts, uniqueness_multi: {
    attribute: 'contact_code_cache'
  }

  validates :domain_statuses, uniqueness_multi: {
    attribute: 'value'
  }

  validates :dnskeys, uniqueness_multi: {
    attribute: 'public_key'
  }

  validate :validate_nameserver_ips

  validate :statuses_uniqueness
  def statuses_uniqueness
    return if statuses.uniq == statuses
    errors.add(:statuses, :taken)
  end

  attr_accessor :registrant_typeahead, :update_me, :deliver_emails,
    :epp_pending_update, :epp_pending_delete, :reserved_pw

  def subordinate_nameservers
    nameservers.select { |x| x.hostname.end_with?(name) }
  end

  def delegated_nameservers
    nameservers.select { |x| !x.hostname.end_with?(name) }
  end

  class << self
    def convert_period_to_time(period, unit)
      return (period.to_i / 365).years if unit == 'd'
      return (period.to_i / 12).years  if unit == 'm'
      return period.to_i.years         if unit == 'y'
    end

    def included
      includes(
        :registrant,
        :registrar,
        :nameservers,
        :whois_record,
        { tech_contacts: :registrar },
        { admin_contacts: :registrar }
      )
    end

    # rubocop: disable Metrics/AbcSize
    # rubocop: disable Metrics/CyclomaticComplexity
    # rubocop: disable Metrics/PerceivedComplexity
    def clean_expired_pendings
      STDOUT << "#{Time.zone.now.utc} - Clean expired domain pendings\n" unless Rails.env.test?

      expire_at = Setting.expire_pending_confirmation.hours.ago
      count = 0
      expired_pending_domains = Domain.where('registrant_verification_asked_at <= ?', expire_at)
      expired_pending_domains.each do |domain|
        unless domain.pending_update? || domain.pending_delete?
          msg = "#{Time.zone.now.utc} - ISSUE: DOMAIN #{domain.id}: #{domain.name} IS IN EXPIRED PENDING LIST, " \
                "but no pendingDelete/pendingUpdate state present!\n"
          STDOUT << msg unless Rails.env.test?
          next
        end
        count += 1
        if domain.pending_update?
          DomainMailer.pending_update_expired_notification_for_new_registrant(domain).deliver_now
        end
        if domain.pending_delete?
          DomainMailer.pending_delete_expired_notification(domain).deliver_now
        end
        domain.clean_pendings!
        STDOUT << "#{Time.zone.now.utc} Domain.clean_expired_pendings: ##{domain.id}\n" unless Rails.env.test?
      end
      STDOUT << "#{Time.zone.now.utc} - Successfully cancelled #{count} domain pendings\n" unless Rails.env.test?
      count
    end
    # rubocop: enable Metrics/PerceivedComplexity
    # rubocop: enable Metrics/AbcSize
    # rubocop: enable Metrics/CyclomaticComplexity

    # rubocop: disable Metrics/LineLength
    def start_expire_period
      STDOUT << "#{Time.zone.now.utc} - Expiring domains\n" unless Rails.env.test?

      domains = Domain.where('valid_to <= ?', Time.zone.now)
      domains.each do |domain|
        next unless domain.expirable?
        domain.set_expired
        STDOUT << "#{Time.zone.now.utc} Domain.start_expire_period: ##{domain.id} #{domain.changes}\n" unless Rails.env.test?
        domain.save(validate: false)
      end

      STDOUT << "#{Time.zone.now.utc} - Successfully expired #{domains.count} domains\n" unless Rails.env.test?
    end

    def start_redemption_grace_period
      STDOUT << "#{Time.zone.now.utc} - Setting server_hold to domains\n" unless Rails.env.test?

      d = Domain.where('outzone_at <= ?', Time.zone.now)
      d.each do |domain|
        next unless domain.server_holdable?
        domain.statuses << DomainStatus::SERVER_HOLD
        STDOUT << "#{Time.zone.now.utc} Domain.start_redemption_grace_period: ##{domain.id} #{domain.changes}\n" unless Rails.env.test?
        domain.save
      end

      STDOUT << "#{Time.zone.now.utc} - Successfully set server_hold to #{d.count} domains\n" unless Rails.env.test?
    end

    def start_delete_period
      STDOUT << "#{Time.zone.now.utc} - Setting delete_candidate to domains\n" unless Rails.env.test?

      d = Domain.where('delete_at <= ?', Time.zone.now)
      d.each do |domain|
        next unless domain.delete_candidateable?
        domain.statuses << DomainStatus::DELETE_CANDIDATE
        STDOUT << "#{Time.zone.now.utc} Domain.start_delete_period: ##{domain.id} #{domain.changes}\n" unless Rails.env.test?
        domain.save
      end

      return if Rails.env.test?
      STDOUT << "#{Time.zone.now.utc} - Successfully set delete_candidate to #{d.count} domains\n"
    end

    # rubocop:disable Rails/FindEach
    def destroy_delete_candidates
      STDOUT << "#{Time.zone.now.utc} - Destroying domains\n" unless Rails.env.test?

      c = 0
      Domain.where("statuses @> '{deleteCandidate}'::varchar[]").each do |x|
        x.destroy
        STDOUT << "#{Time.zone.now.utc} Domain.destroy_delete_candidates: by deleteCandidate ##{x.id}\n" unless Rails.env.test?
        c += 1
      end

      Domain.where('force_delete_at <= ?', Time.zone.now).each do |x|
        x.destroy
        STDOUT << "#{Time.zone.now.utc} Domain.destroy_delete_candidates: by force delete time ##{x.id}\n" unless Rails.env.test?
        c += 1
      end

      STDOUT << "#{Time.zone.now.utc} - Successfully destroyed #{c} domains\n" unless Rails.env.test?
    end
    # rubocop:enable Rails/FindEach
    # rubocop: enable Metrics/LineLength
  end

  def name=(value)
    value.strip!
    value.downcase!
    self[:name] = SimpleIDN.to_unicode(value)
    self[:name_puny] = SimpleIDN.to_ascii(value)
    self[:name_dirty] = value
  end

  def roid
    "EIS-#{id}"
  end

  def puny_label
    name_puny.to_s.split('.').first
  end

  def registrant_typeahead
    @registrant_typeahead || registrant.try(:name) || nil
  end

  def in_reserved_list?
    ReservedDomain.pw_for(name).present?
  end

  def pending_transfer
    domain_transfers.find_by(status: DomainTransfer::PENDING)
  end

  def expirable?
    return false if valid_to > Time.zone.now
    !statuses.include?(DomainStatus::EXPIRED)
  end

  def server_holdable?
    return false if outzone_at > Time.zone.now
    return false if statuses.include?(DomainStatus::SERVER_HOLD)
    return false if statuses.include?(DomainStatus::SERVER_MANUAL_INZONE)
    true
  end

  def delete_candidateable?
    return false if delete_at > Time.zone.now
    return false if statuses.include?(DomainStatus::DELETE_CANDIDATE)
    return false if statuses.include?(DomainStatus::SERVER_DELETE_PROHIBITED)
    true
  end

  def renewable?
    if Setting.days_to_renew_domain_before_expire != 0
      if ((valid_to - Time.zone.now.beginning_of_day).to_i / 1.day) + 1 > Setting.days_to_renew_domain_before_expire
        return false
      end
    end

    return false if statuses.include?(DomainStatus::DELETE_CANDIDATE)

    true
  end

  def poll_message!(message_key)
    registrar.messages.create!(
      body: "#{I18n.t(message_key)}: #{name}",
      attached_obj_id: id,
      attached_obj_type: self.class.to_s
    )
  end

  def preclean_pendings
    self.registrant_verification_token = nil
    self.registrant_verification_asked_at = nil
  end

  def clean_pendings!
    preclean_pendings
    self.pending_json = {}
    statuses.delete(DomainStatus::PENDING_UPDATE)
    statuses.delete(DomainStatus::PENDING_DELETE)
    status_notes[DomainStatus::PENDING_UPDATE] = ''
    status_notes[DomainStatus::PENDING_DELETE] = ''
    save
  end

  def pending_update!
    return true if pending_update?
    self.epp_pending_update = true # for epp

    return true unless registrant_verification_asked?
    pending_json_cache = pending_json
    token = registrant_verification_token
    asked_at = registrant_verification_asked_at
    changes_cache = changes
    new_registrant_id    = registrant.id
    new_registrant_email = registrant.email
    new_registrant_name  = registrant.name

    DomainMailer.pending_update_request_for_old_registrant(self).deliver_now
    DomainMailer.pending_update_notification_for_new_registrant(self).deliver_now

    reload # revert back to original

    self.pending_json = pending_json_cache
    self.registrant_verification_token = token
    self.registrant_verification_asked_at = asked_at
    set_pending_update
    pending_json['domain'] = changes_cache
    pending_json['new_registrant_id']    = new_registrant_id
    pending_json['new_registrant_email'] = new_registrant_email
    pending_json['new_registrant_name']  = new_registrant_name

    # This pending_update! method is triggered by before_update
    # Note, all before_save callbacks are excecuted before before_update,
    # thus automatic statuses has already excectued by this point
    # and we need to trigger automatic statuses manually (second time).
    manage_automatic_statuses
  end

  # rubocop: disable Metrics/CyclomaticComplexity
  def registrant_update_confirmable?(token)
    return true if Rails.env.development?
    return false unless pending_update?
    return false if registrant_verification_token.blank?
    return false if registrant_verification_asked_at.blank?
    return false if token.blank?
    return false if registrant_verification_token != token
    true
  end

  def registrant_delete_confirmable?(token)
    return true if Rails.env.development?
    return false unless pending_delete?
    return false if registrant_verification_token.blank?
    return false if registrant_verification_asked_at.blank?
    return false if token.blank?
    return false if registrant_verification_token != token
    true
  end
  # rubocop: enable Metrics/CyclomaticComplexity

  def force_deletable?
    !statuses.include?(DomainStatus::FORCE_DELETE)
  end

  def registrant_verification_asked?
    registrant_verification_asked_at.present? && registrant_verification_token.present?
  end

  def registrant_verification_asked!(frame_str, current_user_id)
    pending_json['frame'] = frame_str
    pending_json['current_user_id'] = current_user_id
    self.registrant_verification_asked_at = Time.zone.now
    self.registrant_verification_token = SecureRandom.hex(42)
  end

  def pending_delete!
    return true if pending_delete?
    self.epp_pending_delete = true # for epp

    return true unless registrant_verification_asked?
    set_pending_delete
    save(validate: false) # should check if this did succeed

    DomainMailer.pending_deleted(self).deliver_now
  end

  def pricelist(operation, period_i = nil, unit = nil)
    period_i ||= period
    unit ||= period_unit

    zone = name.split('.').drop(1).join('.')

    p = period_i / 365 if unit == 'd'
    p = period_i / 12 if unit == 'm'
    p = period_i if unit == 'y'

    if p > 1
      p = "#{p}years"
    else
      p = "#{p}year"
    end

    Pricelist.pricelist_for(zone, operation, p)
  end

  ### VALIDATIONS ###

  def validate_nameserver_ips
    nameservers.each do |ns|
      next unless ns.hostname.end_with?(name)
      next if ns.ipv4.present?
      errors.add(:nameservers, :invalid) if errors[:nameservers].blank?
      ns.errors.add(:ipv4, :blank)
    end
  end

  def validate_period
    return unless period.present?
    if period_unit == 'd'
      valid_values = %w(365 730 1095)
    elsif period_unit == 'm'
      valid_values = %w(12 24 36)
    else
      valid_values = %w(1 2 3)
    end

    errors.add(:period, :out_of_range) unless valid_values.include?(period.to_s)
  end

  # used for highlighting form tabs
  def parent_valid?
    assoc_errors = errors.keys.select { |x| x.match(/\./) }
    (errors.keys - assoc_errors).empty?
  end

  ## SHARED

  def name_in_wire_format
    res = ''
    parts = name.split('.')
    parts.each do |x|
      res += format('%02X', x.length) # length of label in hex
      res += x.each_byte.map { |b| format('%02X', b) }.join # label
    end

    res += '00'

    res
  end

  def to_s
    name
  end

  def pending_registrant
    return '' if pending_json.blank?
    return '' if pending_json['domain']['registrant_id'].blank?
    Registrant.find_by(id: pending_json['domain']['registrant_id'].last)
  end

  def generate_auth_info
    return if auth_info.present?
    generate_auth_info!
  end

  # rubocop:disable Lint/Loop
  def generate_auth_info!
    begin
      self.auth_info = SecureRandom.hex
    end while self.class.exists?(auth_info: auth_info)
  end
  # rubocop:enable Lint/Loop

  def set_validity_dates
    self.registered_at = Time.zone.now
    self.valid_from = Time.zone.now
    self.valid_to = valid_from + self.class.convert_period_to_time(period, period_unit)
    self.outzone_at = valid_to + Setting.expire_warning_period.days
    self.delete_at = outzone_at + Setting.redemption_grace_period.days
  end

  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/MethodLength
  def set_force_delete
    self.statuses_backup = statuses
    statuses.delete(DomainStatus::CLIENT_DELETE_PROHIBITED)
    statuses.delete(DomainStatus::SERVER_DELETE_PROHIBITED)
    statuses.delete(DomainStatus::PENDING_UPDATE)
    statuses.delete(DomainStatus::PENDING_TRANSFER)
    statuses.delete(DomainStatus::PENDING_RENEW)
    statuses.delete(DomainStatus::PENDING_CREATE)

    statuses.delete(DomainStatus::FORCE_DELETE)
    statuses.delete(DomainStatus::SERVER_RENEW_PROHIBITED)
    statuses.delete(DomainStatus::SERVER_TRANSFER_PROHIBITED)
    statuses.delete(DomainStatus::SERVER_UPDATE_PROHIBITED)
    statuses.delete(DomainStatus::SERVER_MANUAL_INZONE)
    statuses.delete(DomainStatus::PENDING_DELETE)

    statuses << DomainStatus::FORCE_DELETE
    statuses << DomainStatus::SERVER_RENEW_PROHIBITED
    statuses << DomainStatus::SERVER_TRANSFER_PROHIBITED
    statuses << DomainStatus::SERVER_UPDATE_PROHIBITED
    statuses << DomainStatus::PENDING_DELETE

    if (statuses & [DomainStatus::SERVER_HOLD, DomainStatus::CLIENT_HOLD]).empty?
      statuses << DomainStatus::SERVER_MANUAL_INZONE
    end

    self.force_delete_at = Time.zone.now + Setting.redemption_grace_period.days unless force_delete_at
    transaction do
      save!(validate: false)
      registrar.messages.create!(
        body: I18n.t('force_delete_set_on_domain', domain: name)
      )
      return true
    end
    false
  end
  # rubocop: enable Metrics/MethodLength
  # rubocop:enable Metrics/AbcSize

  def unset_force_delete
    s = []
    s << DomainStatus::EXPIRED if statuses.include?(DomainStatus::EXPIRED)
    s << DomainStatus::SERVER_HOLD if statuses.include?(DomainStatus::SERVER_HOLD)
    s << DomainStatus::DELETE_CANDIDATE if statuses.include?(DomainStatus::DELETE_CANDIDATE)

    self.statuses = (statuses_backup + s).uniq

    self.force_delete_at = nil
    self.statuses_backup = []
    save(validate: false)
  end

  def set_expired
    # TODO: currently valid_to attribute update logic is open
    # self.valid_to = valid_from + self.class.convert_period_to_time(period, period_unit)
    self.outzone_at = Time.zone.now + Setting.expire_warning_period.days
    self.delete_at  = Time.zone.now + Setting.redemption_grace_period.days
    statuses << DomainStatus::EXPIRED
  end

  def set_expired!
    set_expired
    save(validate: false)
  end

  def pending_update?
    statuses.include?(DomainStatus::PENDING_UPDATE) && !statuses.include?(DomainStatus::FORCE_DELETE)
  end

  # public api
  def update_prohibited?
    pending_update_prohibited? && pending_delete_prohibited?
  end

  # public api
  def delete_prohibited?
    statuses.include?(DomainStatus::FORCE_DELETE)
  end

  def pending_update_prohibited?
    (statuses & [
      DomainStatus::CLIENT_UPDATE_PROHIBITED,
      DomainStatus::SERVER_UPDATE_PROHIBITED,
      DomainStatus::PENDING_CREATE,
      DomainStatus::PENDING_UPDATE,
      DomainStatus::PENDING_DELETE,
      DomainStatus::PENDING_RENEW,
      DomainStatus::PENDING_TRANSFER
    ]).present?
  end

  def set_pending_update
    if pending_update_prohibited?
      logger.info "DOMAIN STATUS UPDATE ISSUE ##{id}: PENDING_UPDATE not allowed to set. [#{statuses}]"
      return nil
    end
    statuses << DomainStatus::PENDING_UPDATE
  end

  def pending_delete?
    statuses.include?(DomainStatus::PENDING_DELETE) && !statuses.include?(DomainStatus::FORCE_DELETE)
  end

  def pending_delete_prohibited?
    (statuses & [
      DomainStatus::CLIENT_DELETE_PROHIBITED,
      DomainStatus::SERVER_DELETE_PROHIBITED,
      DomainStatus::PENDING_CREATE,
      DomainStatus::PENDING_UPDATE,
      DomainStatus::PENDING_DELETE,
      DomainStatus::PENDING_RENEW,
      DomainStatus::PENDING_TRANSFER
    ]).present?
  end

  def set_pending_delete
    if pending_delete_prohibited?
      logger.info "DOMAIN STATUS UPDATE ISSUE ##{id}: PENDING_DELETE not allowed to set. [#{statuses}]"
      return nil
    end
    statuses << DomainStatus::PENDING_DELETE
  end

  def manage_automatic_statuses
    # domain_statuses.create(value: DomainStatus::DELETE_CANDIDATE) if delete_candidateable?
    if statuses.empty? && valid?
      statuses << DomainStatus::OK
    elsif statuses.length > 1 || !valid?
      statuses.delete(DomainStatus::OK)
    end
  end

  def children_log
    log = HashWithIndifferentAccess.new
    log[:admin_contacts] = admin_contacts.map(&:attributes)
    log[:tech_contacts]  = tech_contacts.map(&:attributes)
    log[:nameservers]    = nameservers.map(&:attributes)
    log[:registrant]     = [registrant.try(:attributes)]
    log[:domain_statuses] = domain_statuses.map(&:attributes)
    log
  end

  def update_whois_record
    whois_record.blank? ? create_whois_record : whois_record.save
  end

  def status_notes_array=(notes)
    self.status_notes = {}
    notes ||= []
    statuses.each_with_index do |status, i|
      status_notes[status] = notes[i]
    end
  end
end
# rubocop: enable Metrics/ClassLength
